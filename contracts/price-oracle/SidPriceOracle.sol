pragma solidity >=0.8.4;
import "@openzeppelin/contracts/access/Ownable.sol";
import "../common/StringUtils.sol";
import "../giftcard/SidGiftCardLedger.sol";
import "./ISidPriceOracle.sol";
import "./interfaces/AggregatorInterface.sol";
import "../giftcard/SidGiftCardVoucher.sol";

// StablePriceOracle sets a price in USD, based on an oracle.
contract SidPriceOracle is ISidPriceOracle, Ownable {
    using StringUtils for *;
    //price in USD per second
    uint256 private constant price1Letter = 100000000000000;
    uint256 private constant price2Letter = 50000000000000;
    uint256 private constant price3Letter = 20597680029427;
    uint256 private constant price4Letter = 5070198161089;
    uint256 private constant price5Letter = 158443692534;

    // Oracle address
    AggregatorInterface public immutable usdOracle;
    SidGiftCardLedger public immutable ledger;
    SidGiftCardVoucher public immutable voucher;

    constructor(AggregatorInterface _usdOracle, SidGiftCardLedger _ledger, SidGiftCardVoucher _voucher) {
        usdOracle = _usdOracle;
        ledger = _ledger;
        voucher = _voucher;
    }

    function giftCardPriceInBNB(uint256[] calldata ids, uint256[] calldata amounts) public view returns (ISidPriceOracle.Price memory) {
        uint256 total = voucher.totalValue(ids, amounts);
        return ISidPriceOracle.Price({base: attoUSDToWei(total), premium: 0, usedPoint: 0});
    }

    function domainPriceInBNB(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view returns (ISidPriceOracle.Price memory) {
        uint256 len = name.strlen();
        uint256 basePrice;
        if (len == 1) {
            basePrice = price1Letter * duration;
        } else if (len == 2) {
            basePrice = price2Letter * duration;
        } else if (len == 3) {
            basePrice = price3Letter * duration;
        } else if (len == 4) {
            basePrice = price4Letter * duration;
        } else {
            basePrice = price5Letter * duration;
        }
        return ISidPriceOracle.Price({base: attoUSDToWei(basePrice), premium: 0, usedPoint: 0});
    }

    function domainPriceWithPointRedemptionInBNB(
        string calldata name,
        uint256 expires,
        uint256 duration,
        address owner
    ) external view returns (ISidPriceOracle.Price memory) {
        uint256 len = name.strlen();
        uint256 basePrice;
        uint256 usedPoint;
        if (len == 1) {
            basePrice = price1Letter * duration;
        } else if (len == 2) {
            basePrice = price2Letter * duration;
        } else if (len == 3) {
            basePrice = price3Letter * duration;
        } else if (len == 4) {
            basePrice = price4Letter * duration;
        } else {
            basePrice = price5Letter * duration;
        }
        uint256 pointRedemption = ledger.balanceOf(owner);
        if (pointRedemption > basePrice) {
            usedPoint = basePrice;
            basePrice = 0;
        } else {
            basePrice = basePrice - pointRedemption;
            usedPoint = pointRedemption;
        }
        return ISidPriceOracle.Price({base: attoUSDToWei(basePrice), premium: 0, usedPoint: usedPoint});
    }

    function attoUSDToWei(uint256 amount) internal view returns (uint256) {
        uint256 bnbPrice = uint256(usdOracle.latestAnswer());
        return (amount * 1e8) / bnbPrice;
    }
}
