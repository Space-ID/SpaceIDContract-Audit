pragma solidity >=0.8.4;

import { Auction } from './Auction.sol';
import "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionFactory is Ownable {
    address[] public auctions;
    mapping(string => address) public auctionDics;

    event AuctionCreated(address auctionContract, address owner, uint numAuctions, address[] allAuctions);

    constructor() {
    }

    function createAuction(address owner,
                           uint startPrices,
                           uint startBlock,
                           uint endBlock,
                           string memory name,
                           address[] memory _addresses) public onlyOwner {
        Auction newAuction = new Auction(owner, startPrices, startBlock, endBlock, name, _addresses);
        auctions.push(address(newAuction));
        auctionDics[name] = address(newAuction);
        emit AuctionCreated(address(newAuction), owner, auctions.length, auctions);
    }

    function allAuctions() public view returns (address[] memory ) {
        return auctions;
    }

    function getAuction(string memory name) public view returns(address) {
        return auctionDics[name];
    }
}
