pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import "../registry/SID.sol";
import "./BNBRegistrarControllerV1.sol";
import "./IBNBRegistrarController.sol";
import "../resolvers/Resolver.sol";
import "./IBulkRenewal.sol";
import "./IPriceOracle.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract BulkRenewal is IBulkRenewal {
    bytes32 private constant BNB_NAMEHASH =
        0xdba5666821b22671387fe7ea11d7cc41ede85a5aa67c3e7b3d68ce6a661f389c;

    SID public immutable sid;

    constructor(SID _sid) {
        sid = _sid;
    }

    function getController() internal view returns (BNBRegistrarController) {
        Resolver r = Resolver(sid.resolver(BNB_NAMEHASH));
        return
            BNBRegistrarController(
                r.interfaceImplementer(
                    BNB_NAMEHASH,
                    type(IBNBRegistrarController).interfaceId
                )
            );
    }

    function rentPrice(string[] calldata names, uint256 duration)
        external
        view
        override
        returns (uint256 total)
    {
        BNBRegistrarController controller = getController();
        for (uint256 i = 0; i < names.length; i++) {
            IPriceOracle.Price memory price = controller.rentPrice(
                names[i],
                duration
            );
            total += (price.base + price.premium);
        }
    }

    function renewAll(string[] calldata names, uint256 duration)
        external
        payable
        override
    {
        BNBRegistrarController controller = getController();
        for (uint256 i = 0; i < names.length; i++) {
            IPriceOracle.Price memory price = controller.rentPrice(
                names[i],
                duration
            );
            controller.renew{value: price.base + price.premium}(
                names[i],
                duration
            );
        }
        // Send any excess funds back
        payable(msg.sender).transfer(address(this).balance);
    }

    function supportsInterface(bytes4 interfaceID)
        external
        pure
        returns (bool)
    {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IBulkRenewal).interfaceId;
    }
}
