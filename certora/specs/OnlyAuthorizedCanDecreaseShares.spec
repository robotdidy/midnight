// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function sharesOf(bytes20 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.price() external => NONDET;
}

/// An unauthorized caller cannot decrease a user's shares except via take.
rule onlyAuthorizedCanDecreaseSharesExceptTake(env e, method f, bytes20 id, address user) {
    uint256 sharesBefore = sharesOf(id, user);

    require user != e.msg.sender;
    require !isAuthorized(user, e.msg.sender);

    calldataarg args;
    f(e, args);

    assert sharesOf(id, user) >= sharesBefore
        || f.selector == sig:take(uint256,address,address,bytes,address,Midnight.Offer,Midnight.Signature,bytes32,bytes32[]).selector;
}

/// In take, the caller must be authorized by the taker and only the lender shares can decrease
rule takeOnlyAuthorizedSellerSharesDecrease(
    env e, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    Midnight.Offer offer, Midnight.Signature signature,
    bytes32 root, bytes32[] proof,
    bytes20 id, address user
) {
    address seller = offer.buy ? taker : offer.maker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert takerUnauthorized => lastReverted;
    assert sharesOf(id, user) < sharesBefore => user == seller;
}
