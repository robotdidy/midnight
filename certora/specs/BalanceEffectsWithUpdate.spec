// SPDX-License-Identifier: GPL-2.0-or-later

// The file is separate from BalanceEffects.spec because it cannot use a mulDiv summary.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;

    function updatePositionView(Midnight.Obligation memory, bytes32, address) external returns (uint128, uint128, uint128);

    function _.price() external => NONDET;

    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

/// UPDATE POSITION ///

/// updatePosition sets user's credit to the post-update value
/// and only changes credit of user and PASSIVE_FEE_RECIPIENT at the obligation id.
rule updatePositionEffects(env e, Midnight.Obligation obligation, address user, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    address passiveFeeRecipient = Utils.passiveFeeRecipient();

    require user != passiveFeeRecipient;

    uint128 updatedCreditBefore;
    updatedCreditBefore, _, _ = updatePositionView(e, obligation, id, user);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    updatePosition(e, obligation, user);

    assert creditOf(id, user) == updatedCreditBefore;
    assert debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyId != id || (anyUser != user && anyUser != passiveFeeRecipient) => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-update credit by exactly units
/// and only changes credit of onBehalf and PASSIVE_FEE_RECIPIENT at the obligation id.
rule withdrawEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    address passiveFeeRecipient = Utils.passiveFeeRecipient();

    require onBehalf != passiveFeeRecipient;

    uint128 updatedCreditBefore;
    updatedCreditBefore, _, _ = updatePositionView(e, obligation, id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    withdraw(e, obligation, units, onBehalf, receiver);

    assert creditOf(id, onBehalf) == updatedCreditBefore - units;
    assert debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyId != id || (anyUser != onBehalf && anyUser != passiveFeeRecipient) => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// TAKE ///

/// take changes maker's and taker's net credit-debt by +/- units relative to their post-update values
/// and only changes credit of maker, taker, and PASSIVE_FEE_RECIPIENT and debt of maker and taker at the obligation id.
rule takeEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);
    address passiveFeeRecipient = Utils.passiveFeeRecipient();

    require offer.maker != passiveFeeRecipient;
    require taker != passiveFeeRecipient;

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
