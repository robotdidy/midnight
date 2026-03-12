// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Midnight} from "../Midnight.sol";
import {Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    /// @dev Returns the expected total units and total shares.
    function expectedTakeState(Midnight midnight, bytes32 id, address taker, Offer memory offer)
        internal
        view
        returns (uint256, uint256)
    {
        (uint256 makerAccruedFee, uint256 makerFeeShares) =
            midnight.accrueContinuousFeeView(offer.obligation, id, offer.maker);
        (uint256 takerAccruedFee, uint256 takerFeeShares) =
            midnight.accrueContinuousFeeView(offer.obligation, id, taker);
        return (
            midnight.totalUnits(id) + makerAccruedFee + takerAccruedFee,
            midnight.totalShares(id) + makerFeeShares + takerFeeShares
        );
    }

    // Forward: units = shares.mulDivUp/Down(totalUnits + 1, totalShares + 1) depending on buyerIsLender.
    // When buyerIsLender (forward rounds up): inverse rounds down.
    // When !buyerIsLender (forward rounds down): inverse rounds up.
    function expectedUnitsToShares(
        Midnight midnight,
        bytes32 id,
        address taker,
        Offer memory offer,
        uint256 targetUnits
    ) internal view returns (uint256) {
        (uint256 totalUnits, uint256 totalShares) = expectedTakeState(midnight, id, taker, offer);
        address buyer = offer.buy ? offer.maker : taker;
        bool buyerIsLender = midnight.debtOf(id, buyer) == 0; // accrued fee is 0 if debt is 0
        return buyerIsLender
            ? targetUnits.mulDivDown(totalShares + 1, totalUnits + 1)
            : targetUnits.mulDivUp(totalShares + 1, totalUnits + 1);
    }

    // Forward: buyerAssets = offer.buy ? unitsDown.mulDivDown(buyerPrice, WAD) : unitsUp.mulDivUp(buyerPrice, WAD).
    /// @dev Should not be used if buyerPrice > WAD, because not all buyerAssets are reachable then.
    function expectedBuyerAssetsToShares(
        Midnight midnight,
        bytes32 id,
        address taker,
        Offer memory offer,
        uint256 targetBuyerAssets
    ) internal view returns (uint256) {
        (uint256 totalUnits, uint256 totalShares) = expectedTakeState(midnight, id, taker, offer);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 _tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 buyerPrice = offer.buy ? offerPrice : offerPrice + _tradingFee;
        require(buyerPrice <= WAD, "buyerPrice");
        if (offer.buy) {
            return targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivUp(totalShares + 1, totalUnits + 1);
        } else {
            return targetBuyerAssets.mulDivDown(WAD, buyerPrice).mulDivDown(totalShares + 1, totalUnits + 1);
        }
    }

    // Forward: sellerAssets = offer.buy ? unitsDown.mulDivDown(sellerPrice, WAD) : unitsUp.mulDivUp(sellerPrice, WAD).
    function expectedSellerAssetsToShares(
        Midnight midnight,
        bytes32 id,
        address taker,
        Offer memory offer,
        uint256 targetSellerAssets
    ) internal view returns (uint256) {
        (uint256 totalUnits, uint256 totalShares) = expectedTakeState(midnight, id, taker, offer);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 _tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        if (offer.buy) {
            return targetSellerAssets.mulDivUp(WAD, sellerPrice).mulDivUp(totalShares + 1, totalUnits + 1);
        } else {
            return targetSellerAssets.mulDivDown(WAD, sellerPrice).mulDivDown(totalShares + 1, totalUnits + 1);
        }
    }
}
