// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes20 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.price() external => PER_CALLEE_CONSTANT;

    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}


/// No function other than take can increase a user's debt.
rule debtOnlyIncreasesViaTake(env e, method f, bytes20 id, address user) {
    uint256 debtBefore = debtOf(id, user);

    calldataarg args;
    f(e, args);

    assert debtBefore >= debtOf(id, user)  
        || f.selector == sig:take(uint256,uint256,uint256,uint256,address,address,bytes,address,Midnight.Offer,Midnight.Signature,bytes32,bytes32[]).selector;
}

/// In take, only the taker or the offer maker can have their debt increased.
rule debtOnlyIncreasesForConsentingParties(
    env e, uint256 buyerAssets, uint256 sellerAssets,
    uint256 obligationUnits, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    Midnight.Offer offer, Midnight.Signature signature,
    bytes32 root, bytes32[] proof,
    bytes20 id, address user
) {
    uint256 debtBefore = debtOf(id, user);

    take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares,
         taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller,
         offer, signature, root, proof);

    assert debtOf(id, user) > debtBefore => (user == taker || user == offer.maker);
}
