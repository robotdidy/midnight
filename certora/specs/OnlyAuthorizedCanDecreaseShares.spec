// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function feeRecipient() external returns (address) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function sharesOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    return res;
}

/// An unauthorized caller cannot decrease a user's shares except via take.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant share decreases are not covered.
rule onlyAuthorizedCanDecreaseSharesExceptTake(env e, method f, bytes32 id, address user) {
    uint256 sharesBefore = sharesOf(id, user);
    bool passiveFeeWithdraw = user == Utils.passiveFeeRecipient() && e.msg.sender == feeRecipient() && f.selector == sig:withdraw(Midnight.Obligation, uint256, uint256, address, address).selector;

    require user != e.msg.sender;
    require !isAuthorized(user, e.msg.sender);

    calldataarg args;
    f(e, args);

    assert sharesOf(id, user) >= sharesBefore || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector || passiveFeeWithdraw;
}

/// In take, the caller must be authorized by the taker and only the seller's shares can decrease.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and decrease a different user's shares.
rule takeOnlyAuthorizedSellerSharesDecrease(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    // Exclude passive fee recipient: fee share minting during accrual can change their shares.
    require user != Utils.passiveFeeRecipient();

    address seller = offer.buy ? taker : offer.maker;
    address buyer = offer.buy ? offer.maker : taker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    bool reverted = lastReverted;
    uint256 sharesAfter = sharesOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == seller => sharesAfter <= sharesBefore;
    assert user == buyer => sharesAfter >= sharesBefore;
    assert user != buyer && user != seller => sharesAfter == sharesBefore;
}

/// No function other than take can increase a user's debt beyond accrual.
rule debtOnlyIncreasesViaTake(env e, method f, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector && !f.isView } {
    uint256 debtBefore = debtOf(id, user);
    uint256 pendingFeeBefore = require_uint256(pendingFee(id, user));

    calldataarg args;
    f(e, args);

    assert debtOf(id, user) <= debtBefore + pendingFeeBefore;
}

/// In take, the caller must be authorized by the taker, and only the seller's debt can increase.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and increase a different user's debt.
rule takeOnlyAuthorizedSellerDebtIncrease(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    uint256 pendingFeeBefore = require_uint256(pendingFee(id, user));

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    bool reverted = lastReverted;
    uint256 debtAfter = debtOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == buyer => debtAfter <= debtBefore + pendingFeeBefore;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}
