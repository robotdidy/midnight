// SPDX-License-Identifier: GPL-2.0-or-later

// The file is separate from BalanceEffects.spec because it cannot use a mulDiv summary.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;

    function _.price() external => NONDET;

    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => signerSummary();
}

function signerSummary() returns address {
    address returnedSigner;
    require returnedSigner != Utils.passiveFeeRecipient(), "passive fee recipient can't sign";
    return returnedSigner;
}

/// The passive fee recipient can't authorize another account, because it can't sign
/// and setIsAuthorized requires msg.sender == onBehalf || isAuthorized[onBehalf][msg.sender].
strong invariant feeRecipientCantAuthorize(address authorized)
    !isAuthorized(Utils.passiveFeeRecipient(), authorized)
    {
        preserved with (env e) {
            require e.msg.sender != Utils.passiveFeeRecipient(), "passive fee recipient can't sign or call";
            requireInvariant feeRecipientCantAuthorize(e.msg.sender);
        }
    }

/// The passive fee recipient has no pending fee, because they only receive credit via fee accrual
/// and never participate in take.
strong invariant feeRecipientHasNoPendingFee(bytes32 id)
    pendingFee(id, Utils.passiveFeeRecipient()) == 0
    {
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) with (env e) {
            require e.msg.sender != Utils.passiveFeeRecipient(), "passive fee recipient can't sign or call";
            requireInvariant feeRecipientCantAuthorize(e.msg.sender);
        }
    }

/// UPDATE POSITION ///

/// updatePosition sets user's credit to the post-update value
/// and only changes credit of user and passive fee recipient at the obligation id.
rule updatePositionEffects(env e, Midnight.Obligation obligation, address user, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    address passiveFeeRecipient = Utils.passiveFeeRecipient();

    requireInvariant feeRecipientHasNoPendingFee(id);

    uint128 updatedUserCredit;
    uint128 userFee;
    updatedUserCredit, _, userFee = updatePositionView(e, obligation, id, user);

    uint256 anyCredit = creditOf(anyId, anyUser);
    uint256 anyDebt = debtOf(anyId, anyUser);
    uint256 feeRecipientCredit = creditOf(id, passiveFeeRecipient);

    updatePosition(e, obligation, user);

    assert debtOf(anyId, anyUser) == anyDebt;
    assert (anyId != id) || (anyUser != passiveFeeRecipient && anyUser != user) => creditOf(anyId, anyUser) == anyCredit;
    assert creditOf(id, user) == updatedUserCredit;

    // Premise is needed because fee recipient is not slashed in other user updates.
    assert user != passiveFeeRecipient => creditOf(id, passiveFeeRecipient) == feeRecipientCredit + userFee;
    assert user == passiveFeeRecipient => userFee == 0;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-update credit by exactly units
/// and only changes credit of onBehalf and passive fee recipient at the obligation id.
rule withdrawEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    address passiveFeeRecipient = Utils.passiveFeeRecipient();

    requireInvariant feeRecipientHasNoPendingFee(id);

    uint128 updatedUserCredit;
    uint128 userFee;
    updatedUserCredit, _, userFee = updatePositionView(e, obligation, id, onBehalf);

    uint256 anyCredit = creditOf(anyId, anyUser);
    uint256 anyDebt = debtOf(anyId, anyUser);
    uint256 feeRecipientCredit = creditOf(id, passiveFeeRecipient);

    withdraw(e, obligation, units, onBehalf, receiver);

    assert creditOf(id, onBehalf) == updatedUserCredit - units;
    assert debtOf(anyId, anyUser) == anyDebt;
    assert (anyId != id) || (anyUser != passiveFeeRecipient && anyUser != onBehalf) => creditOf(anyId, anyUser) == anyCredit;

    // Premise is needed because fee recipient is not slashed in other user updates.
    assert onBehalf != passiveFeeRecipient => creditOf(id, passiveFeeRecipient) == feeRecipientCredit + userFee;
}

/// TAKE ///

/// take changes maker's and taker's net credit-debt by +/- units relative to their post-update values
/// and only changes credit of maker, taker, and passive fee recipient and debt of maker and taker at the obligation id.
/// Assumes the passive fee recipient can't sign or call since its address derives from the hash of a human readable string.
rule takeEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);
    address passiveFeeRecipient = Utils.passiveFeeRecipient();

    require e.msg.sender != passiveFeeRecipient, "passive fee recipient can't sign or call";
    requireInvariant feeRecipientCantAuthorize(e.msg.sender);

    uint128 makerCreditBefore;
    makerCreditBefore, _, _ = updatePositionView(e, offer.obligation, id, offer.maker);
    uint128 takerCreditBefore;
    takerCreditBefore, _, _ = updatePositionView(e, offer.obligation, id, taker);
    mathint makerNetBefore = to_mathint(makerCreditBefore) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetBefore = to_mathint(takerCreditBefore) - to_mathint(debtOf(id, taker));
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    mathint makerNetAfter = to_mathint(creditOf(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetAfter = to_mathint(creditOf(id, taker)) - to_mathint(debtOf(id, taker));

    mathint makerDelta = offer.buy ? units : -units;
    assert makerNetAfter == makerNetBefore + makerDelta;
    mathint takerDelta = offer.buy ? -units : units;
    assert takerNetAfter == takerNetBefore + takerDelta;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker && anyUser != passiveFeeRecipient) => creditOf(anyId, anyUser) == otherCreditBefore;
}
