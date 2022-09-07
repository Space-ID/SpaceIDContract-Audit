// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./BaseRegistrarImplementation.sol";
import "./StringUtils.sol";
import "../resolvers/Resolver.sol";
import "../registry/ReverseRegistrar.sol";
import "./IBNBRegistrarController.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../wrapper/INameWrapper.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract BNBRegistrarControllerV4 is Ownable {
    using StringUtils for *;

    uint constant public MIN_REGISTRATION_DURATION = 365 days;
    mapping(address => uint256) public eligibleCount;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private COMMITMENT_CONTROLLER_ID = bytes4(
        keccak256("rentPrice(string,uint256)") ^
        keccak256("available(string)") ^
        keccak256("makeCommitment(string,address,bytes32)") ^
        keccak256("commit(bytes32)") ^
        keccak256("register(string,address,uint256,bytes32)") ^
        keccak256("renew(string,uint256)")
    );

    bytes4 constant private COMMITMENT_WITH_CONFIG_CONTROLLER_ID = bytes4(
        keccak256("registerWithConfig(string,address,uint256,bytes32,address,address)") ^
        keccak256("makeCommitmentWithConfig(string,address,bytes32,address,address)")
    );

    BaseRegistrarImplementation base;
    IPriceOracle prices;
    uint public minCommitmentAge;
    uint public maxCommitmentAge;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrarImplementation _base,
                IPriceOracle _prices, 
                uint _minCommitmentAge, 
                uint _maxCommitmentAge) {
        require(_maxCommitmentAge > _minCommitmentAge);
        base = _base;
        prices = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function rentPrice(string memory name, uint256 duration)
        public
        view
        returns (IPriceOracle.Price memory price)
    {
        bytes32 label = keccak256(bytes(name));
        price = prices.price(name, base.nameExpires(uint256(label)), duration);
    }


    function valid(string memory name) public pure returns (bool) {
        // check unicode rune count, if rune count is >=3, byte length must be >=3.
        if (name.strlen() < 3) {
            return false;
        }
        bytes memory nb = bytes(name);
        // zero width for /u200b /u200c /u200d and U+FEFF
        for (uint256 i; i < nb.length - 2; i++) {
            if (bytes1(nb[i]) == 0xe2 && bytes1(nb[i + 1]) == 0x80) {
                if (
                    bytes1(nb[i + 2]) == 0x8b ||
                    bytes1(nb[i + 2]) == 0x8c ||
                    bytes1(nb[i + 2]) == 0x8d
                ) {
                    return false;
                }
            } else if (bytes1(nb[i]) == 0xef) {
                if (bytes1(nb[i + 1]) == 0xbb && bytes1(nb[i + 2]) == 0xbf)
                    return false;
            }
        }
        return true;
    }


    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }


    function register(string calldata name, 
                      address owner, 
                      uint duration, 
                      uint256 index) external payable {
        registerWithConfig(name, owner, duration, address(0), address(0));
    }

    
    function _checkPrice(string memory name,
                         uint duration) private returns(uint) {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        uint cost = (price.base + price.premium);
        require(msg.value >= cost);
        require(available(name), "Name not available");
        return cost;
    }


    function registerWithConfig(string memory name,
                                address owner,
                                uint duration,
                                address resolver,
                                address addr) public payable {
        require(eligibleCount[owner]>0, "You are not eligible to claim!");
        require(duration >= MIN_REGISTRATION_DURATION);
        eligibleCount[owner] -= 1;
        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);
        uint cost = _checkPrice(name, duration);

        uint expires;
        if(resolver != address(0)) {
            // Set this contract as the (temporary) owner, giving it
            // permission to set up the resolver.
            expires = base.register(tokenId, address(this), duration);

            // The nodehash of this label
            bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

            // Set the resolver
            base.sid().setResolver(nodehash, resolver);

            // Configure the resolver
            if (addr != address(0)) {
                Resolver(resolver).setAddr(nodehash, addr);
            }

            // Now transfer full ownership to the expeceted owner
            base.reclaim(tokenId, owner);
            base.transferFrom(address(this), owner, tokenId);
        } else {
            require(addr == address(0));
            expires = base.register(tokenId, owner, duration);
        }

        emit NameRegistered(name, label, owner, cost, expires);

        // Refund any extra payment
        if(msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    function renew(string calldata name, uint duration) external payable {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        uint256 cost = (price.base + price.premium);
        require(msg.value >= cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        if(msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit NameRenewed(name, label, cost, expires);
    }

    function setPriceOracle(IPriceOracle _prices) public onlyOwner {
        require(address(_prices) != address(0), "address can not be zero!");
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }


    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == COMMITMENT_CONTROLLER_ID ||
               interfaceID == COMMITMENT_WITH_CONFIG_CONTROLLER_ID;
    }

    function setEligiableCount(address addr, uint256 count) public onlyOwner {
        eligibleCount[addr] = count;
    }

    function batchSetEligiableCount(address[] memory addr, uint256[] memory count) public onlyOwner {
        require(addr.length == count.length, "two arrays length must be the same!");
        for (uint i=0; i<addr.length; i++) {
            setEligiableCount(addr[i], count[i]);
        }
    }
}
