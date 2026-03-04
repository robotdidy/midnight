// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.price() external => NONDET;
}

/// No function other than take can increase a user's debt.
rule debtOnlyIncreasesViaTake(env e, method f, bytes32 id, address user) {
    uint256 debtBefore = debtOf(id, user);

    calldataarg args;
    f(e, args);

    assert debtBefore >= debtOf(id, user) || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector;
}

/// In take, only the seller can newly become a borrower; the buyer can only reduce debt; third parties are unaffected.
rule takeOnlySellerBecomesBorrower(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    uint256 debtBefore = debtOf(id, user);

    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    uint256 debtAfter = debtOf(id, user);

    assert user == buyer => debtAfter <= debtBefore;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}
