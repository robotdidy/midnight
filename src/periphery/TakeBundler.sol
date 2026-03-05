// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Midnight} from "../Midnight.sol";
import {Offer, Signature} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler {
    using UtilsLib for uint256;

    struct Take {
        uint256 obligationShares;
        Offer offer;
        Signature sig;
        bytes32 root;
        bytes32[] proof;
    }

    /// @dev Iterates through orders, filling up to `targetShares` obligation shares total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev minBuyerAssets and maxBuyerAssets bound the total buyer assets to control the average price of the bundle.
    function bundleTakeShares(
        Midnight midnight,
        uint256 targetShares,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");

        uint256 totalFilledShares;
        uint256 totalBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledShares < targetShares; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(targetShares - totalFilledShares, take.obligationShares),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256 filledBuyerAssets, uint256, uint256, uint256 filledObligationShares
            ) {
                totalFilledShares += filledObligationShares;
                totalBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledShares == targetShares, "insufficient liquidity");
        require(totalBuyerAssets >= minBuyerAssets, "average price too low");
        require(totalBuyerAssets <= maxBuyerAssets, "average price too high");
    }

    /// @dev Same as bundleTakeShares but targets obligation units.
    /// @dev unitsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev minBuyerAssets and maxBuyerAssets bound the total buyer assets to control the average price of the bundle.
    function bundleTakeUnits(
        Midnight midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.toId(takes[0].offer.obligation);

        uint256 totalFilledUnits;
        uint256 totalBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.unitsToShares(midnight, id, taker, take.offer, targetUnits - totalFilledUnits),
                    take.obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256 filledBuyerAssets, uint256, uint256 filledObligationUnits, uint256
            ) {
                totalFilledUnits += filledObligationUnits;
                totalBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
        require(totalBuyerAssets >= minBuyerAssets, "average price too low");
        require(totalBuyerAssets <= maxBuyerAssets, "average price too high");
    }

    /// @dev Same as bundleTakeShares but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev minObligationUnits and maxObligationUnits bound the total obligation units to control the average price of
    /// the bundle (buyer assets are already fixed by targetBuyerAssets).
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minObligationUnits,
        uint256 maxObligationUnits
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledBuyerAssets;
        uint256 totalObligationUnits;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < targetBuyerAssets; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToShares(
                        midnight, id, taker, take.offer, targetBuyerAssets - totalFilledBuyerAssets
                    ),
                    take.obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256 filledBuyerAssets, uint256, uint256 filledObligationUnits, uint256
            ) {
                totalFilledBuyerAssets += filledBuyerAssets;
                totalObligationUnits += filledObligationUnits;
            } catch {}
        }

        require(totalFilledBuyerAssets == targetBuyerAssets, "insufficient liquidity");
        require(totalObligationUnits >= minObligationUnits, "average price too low");
        require(totalObligationUnits <= maxObligationUnits, "average price too high");
    }

    /// @dev Same as bundleTakeShares but targets seller assets.
    /// @dev sellerAssetsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev minBuyerAssets and maxBuyerAssets bound the total buyer assets to control the average price of the bundle.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledSellerAssets;
        uint256 totalBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledSellerAssets < targetSellerAssets; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToShares(
                        midnight, id, taker, take.offer, targetSellerAssets - totalFilledSellerAssets
                    ),
                    take.obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256 filledBuyerAssets, uint256 filledSellerAssets, uint256, uint256
            ) {
                totalFilledSellerAssets += filledSellerAssets;
                totalBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledSellerAssets == targetSellerAssets, "insufficient liquidity");
        require(totalBuyerAssets >= minBuyerAssets, "average price too low");
        require(totalBuyerAssets <= maxBuyerAssets, "average price too high");
    }
}
