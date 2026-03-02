// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {MorphoV2} from "../MorphoV2.sol";
import {Offer, Signature} from "../interfaces/IMorphoV2.sol";

contract TakeBundler {
    /// @dev Iterates through orders, filling up to `targetShares` obligation shares total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    function bundleTake(
        MorphoV2 morpho,
        uint256 targetShares,
        address taker,
        address takerCallback,
        bytes calldata takerCallbackData,
        address receiverIfTakerIsSeller,
        Offer[] calldata offers,
        Signature[] calldata sigs,
        bytes32[] calldata roots,
        bytes32[][] calldata proofs
    ) external {
        require(taker == msg.sender || morpho.isAuthorized(taker, msg.sender), "UNAUTHORIZED");

        uint256 filled;

        uint256 i;
        while (i < offers.length && filled < targetShares) {
            try morpho.take(
                targetShares - filled,
                taker,
                takerCallback,
                takerCallbackData,
                receiverIfTakerIsSeller,
                offers[i],
                sigs[i],
                roots[i],
                proofs[i]
            ) returns (
                uint256, uint256, uint256, uint256 obligationShares
            ) {
                filled += obligationShares;
            } catch {}

            ++i;
        }

        require(filled >= targetShares, "insufficient liquidity");
    }
}
