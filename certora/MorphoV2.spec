// SPDX-License-Identifier: GPL-2.0-or-later

/// METHODS ///

methods {}

/// SANITY ///

rule sanity() {
    assert true;
}

rule takeInputs(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, signature, root, proof, takerCallbackAddress, takerCallbackData);

    assert buyerAssets == 0 || buyerAssetsOutput == buyerAssets;
    assert sellerAssets == 0 || sellerAssetsOutput == sellerAssets;
    assert obligationUnits == 0 || obligationUnitsOutput == obligationUnits;
    assert obligationShares == 0 || obligationSharesOutput == obligationShares;
}
