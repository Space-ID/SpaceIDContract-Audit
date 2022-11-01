// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./BaseRegistrarImplementation.sol";
import "./StringUtils.sol";
import "../resolvers/Resolver.sol";
import "../referral/IReferralHub.sol";
import "../giftcard/SidGiftCardLedger.sol";
import "../price-oracle/ISidPriceOracle.sol";
import "./IBNBRegistrarController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev Registrar with giftcard support
 *
 */
contract BNBRegistrarControllerV9 is Ownable {
    using StringUtils for *;

    uint public constant MIN_REGISTRATION_DURATION = 365 days;

    bytes4 private constant INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 private constant COMMITMENT_CONTROLLER_ID =
        bytes4(
            keccak256("rentPrice(string,uint256)") ^
                keccak256("available(string)") ^
                keccak256("makeCommitment(string,address,bytes32)") ^
                keccak256("commit(bytes32)") ^
                keccak256("register(string,address,uint256,bytes32)") ^
                keccak256("renew(string,uint256)")
        );

    bytes4 private constant COMMITMENT_WITH_CONFIG_CONTROLLER_ID =
        bytes4(keccak256("registerWithConfig(string,address,uint256,bytes32,address,address)") ^ keccak256("makeCommitmentWithConfig(string,address,bytes32,address,address)"));

    BaseRegistrarImplementation base;
    SidGiftCardLedger giftCardLedger;
    ISidPriceOracle prices;
    IReferralHub referralHub;
    uint public minCommitmentAge;
    uint public maxCommitmentAge;

    mapping(bytes32 => uint) public commitments;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(
        BaseRegistrarImplementation _base,
        ISidPriceOracle _prices,
        SidGiftCardLedger _giftCardLedger,
        IReferralHub _referralHub,
        uint _minCommitmentAge,
        uint _maxCommitmentAge
    ) public {
        require(_maxCommitmentAge > _minCommitmentAge);
        base = _base;
        prices = _prices;
        giftCardLedger = _giftCardLedger;
        referralHub = _referralHub;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function rentPrice(string memory name, uint256 duration) public view returns (ISidPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.domainPriceInBNB(name, base.nameExpires(uint256(label)), duration);
    }

    function rentPriceWithPointRedemption(
        string memory name,
        uint256 duration,
        address registerAddress
    ) public view returns (ISidPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.domainPriceWithPointRedemptionInBNB(name, base.nameExpires(uint256(label)), duration, registerAddress);
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
                if (bytes1(nb[i + 2]) == 0x8b || bytes1(nb[i + 2]) == 0x8c || bytes1(nb[i + 2]) == 0x8d) {
                    return false;
                }
            } else if (bytes1(nb[i]) == 0xef) {
                if (bytes1(nb[i + 1]) == 0xbb && bytes1(nb[i + 2]) == 0xbf) return false;
            }
        }
        return true;
    }

    function available(string memory name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret
    ) public pure returns (bytes32) {
        return makeCommitmentWithConfig(name, owner, secret, address(0), address(0));
    }

    function makeCommitmentWithConfig(
        string memory name,
        address owner,
        bytes32 secret,
        address resolver,
        address addr
    ) public pure returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        if (resolver == address(0) && addr == address(0)) {
            return keccak256(abi.encodePacked(label, owner, secret));
        }
        require(resolver != address(0));
        return keccak256(abi.encodePacked(label, owner, resolver, addr, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + maxCommitmentAge < block.timestamp);
        commitments[commitment] = block.timestamp;
    }

    function register(
        string calldata name,
        address owner,
        uint duration,
        bytes32 secret
    ) external payable {
        registerWithConfigAndPoint(name, owner, duration, secret, address(0), address(0), false, bytes32(0));
    }

    function registerWithConfig(
        string memory name,
        address owner,
        uint duration,
        bytes32 secret,
        address resolver,
        address addr
    ) public payable {
        registerWithConfigAndPoint(name, owner, duration, secret, resolver, addr, false, bytes32(0));
    }

    function registerWithConfigAndPoint (
        string memory name,
        address owner,
        uint duration,
        bytes32 secret,
        address resolver,
        address addr,
        bool isUseGiftCard,
        bytes32 nodehash
    ) public payable {
        bytes32 commitment = makeCommitmentWithConfig(name, owner, secret, resolver, addr);
        uint cost = _consumeCommitment(name, duration, commitment, isUseGiftCard);

        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        uint expires;
        if (resolver != address(0)) {
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

        //Check is eligible for referral program
        if (nodehash != bytes32(0)) {
            (bool isEligible, address resolvedAddress) = referralHub.isReferralEligible(nodehash);
            if (isEligible && nodehash != bytes32(0)) {
                referralHub.addNewReferralRecord(nodehash);
                (uint256 referrerFee, uint256 referreeFee) = referralHub.getReferralCommisionFee(cost, nodehash);
                if (referrerFee > 0) {
                    referralHub.deposit{value: referrerFee}(resolvedAddress);
                }
                cost = cost - referreeFee;
            }
        }

        // Refund any extra payment
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    function renew(string calldata name, uint duration) external payable {
        renewWithPoint(name, duration, false);
    }

    function renewWithPoint(
        string calldata name,
        uint duration,
        bool isUsePoints
    ) public payable {
        ISidPriceOracle.Price memory price;
        if (isUsePoints) {
            price = rentPriceWithPointRedemption(name, duration, msg.sender);
            //deduct points from gift card ledger
            giftCardLedger.deduct(msg.sender, price.usedPoint);
        } else {
            price = rentPrice(name, duration);
        }
        uint256 cost = (price.base + price.premium);
        require(msg.value >= cost);
        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        // Refund any extra payment
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit NameRenewed(name, label, cost, expires);
    }

    function setPriceOracle(ISidPriceOracle _prices) public onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }

    function setCommitmentAges(uint _minCommitmentAge, uint _maxCommitmentAge) public onlyOwner {
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID || interfaceID == COMMITMENT_CONTROLLER_ID || interfaceID == COMMITMENT_WITH_CONFIG_CONTROLLER_ID;
    }

    function _consumeCommitment(
        string memory name,
        uint duration,
        bytes32 commitment,
        bool usePoints
    ) internal returns (uint256) {
        // Require a valid commitment
        require(commitments[commitment] + minCommitmentAge <= block.timestamp);
        // If the commitment is too old, or the name is registered, stop
        require(commitments[commitment] + maxCommitmentAge > block.timestamp);
        require(available(name));
        delete (commitments[commitment]);
        ISidPriceOracle.Price memory price;
        if (usePoints) {
            uint256 senderBalance = giftCardLedger.balanceOf(msg.sender);
            price = rentPriceWithPointRedemption(name, duration, msg.sender);
            //deduct points from gift card ledger
            giftCardLedger.deduct(msg.sender, price.usedPoint);
            assert(senderBalance == 0 || senderBalance > giftCardLedger.balanceOf(msg.sender));
        } else {
            price = rentPrice(name, duration);
        }
        uint cost = (price.base + price.premium);
        require(duration >= MIN_REGISTRATION_DURATION);
        require(msg.value >= cost);
        return cost;
    }
}
