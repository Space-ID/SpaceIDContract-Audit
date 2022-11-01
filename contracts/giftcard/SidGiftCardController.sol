// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "./SidGiftCardRegistrar.sol";
import "../price-oracle/ISidPriceOracle.sol";
import "./SidGiftCardVoucher.sol";

contract SidGiftCardController is Ownable{
    SidGiftCardRegistrar public registrar;
    ISidPriceOracle public priceOracle;
    SidGiftCardVoucher public voucher;
    
    constructor(SidGiftCardRegistrar _registrar, ISidPriceOracle _priceOracle, SidGiftCardVoucher _voucher) {
        registrar = _registrar;
        priceOracle = _priceOracle;
        voucher = _voucher;
    }

    function price(uint256[] calldata ids, uint256[] calldata amounts) external view returns (uint256) {
        return priceOracle.giftCardPriceInBNB(ids, amounts).base;
    }

    function batchRegister(uint256[] calldata ids, uint256[] calldata amounts) external payable {
        require(voucher.isValidVoucherIds(ids), "Invalid voucher id");
        uint256 cost = priceOracle.giftCardPriceInBNB(ids, amounts).base;
        require(msg.value >= cost, "Insufficient funds");
        registrar.batchRegister(msg.sender, ids, amounts);
        // Refund any extra payment
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    function setNewPriceOracle(ISidPriceOracle _priceOracle) public onlyOwner {
        priceOracle = _priceOracle;
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
