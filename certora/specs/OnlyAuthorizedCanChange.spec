// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function feeRecipient() external returns (address) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function session(address user) external returns (bytes32) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // Summarize oracle calls.
    function _.price() external => NONDET;

    // Summarize complex internal functions irrelevant to authorization checks.
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // Summarize TickLib functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summarize UtilsLib functions.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and tokens do not re-enter Midnight.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// HELPERS ///

definition noAccrual(env e, bytes32 id, address borrower) returns bool = currentContract.position[id][borrower].pendingFee == 0 || e.block.timestamp == currentContract.position[id][borrower].lastAccrual;

/// CREDIT AND DEBT CHANGE RULES ///

/// An unauthorized caller cannot change a user's credit and debt except via take, liquidate, and updatePosition.
/// take is excluded because its special authorization and balance-change behavior is covered by
/// unauthorizedTakeFails, takeRequiresMakerConsent, and takeEffects.
/// PASSIVE_FEE_RECIPIENT's credit can increase via fee accrual without authorization.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptTakeLiquidateAndUpdatePosition(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:updatePosition(Midnight.Obligation, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    bool isPassiveFeeRecipient = user == Utils.passiveFeeRecipient();

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || isPassiveFeeRecipient;
}

/// COLLATERAL CHANGE RULES ///

/// An unauthorized caller cannot change a user's collateral except via liquidate.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant collateral changes are not covered.
rule onlyAuthorizedCanChangeCollateralExceptLiquidate(env e, method f, calldataarg args, bytes32 id, address user, uint256 collateralIndex) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 collateralBefore = collateralOf(id, user, collateralIndex);
    f(e, args);
    uint256 collateralAfter = collateralOf(id, user, collateralIndex);

    assert collateralAfter == collateralBefore || userIsAuthorized;
}

/// CONSUMED CHANGE RULES ///

/// An unauthorized caller cannot change a user's consumed except via take.
/// take is excluded because maker consent is verified via signature/ratification, not caller authorization.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant consumed changes are not covered.
rule onlyAuthorizedCanChangeConsumedExceptTake(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> !f.isView && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 consumedBefore = consumed(user, group);
    f(e, args);
    uint256 consumedAfter = consumed(user, group);

    assert consumedAfter == consumedBefore || userIsAuthorized;
}

/// SESSION CHANGE RULES ///

/// An unauthorized caller cannot change a user's session.
rule onlyAuthorizedCanChangeSession(env e, method f, calldataarg args, address user) filtered { f -> !f.isView } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    bytes32 sessionBefore = session(user);
    f(e, args);
    bytes32 sessionAfter = session(user);

    assert sessionAfter == sessionBefore || userIsAuthorized;
}

/// AUTHORIZATION CHANGE RULES ///

/// An unauthorized caller cannot change a user's isAuthorized mapping.
rule onlyAuthorizedCanChangeIsAuthorized(env e, method f, calldataarg args, address authorizer, address authorized) filtered { f -> !f.isView } {
    bool authorizerIsAuthorized = authorizer == e.msg.sender || isAuthorized(authorizer, e.msg.sender);

    bool isAuthorizedBefore = isAuthorized(authorizer, authorized);
    f(e, args);
    bool isAuthorizedAfter = isAuthorized(authorizer, authorized);

    assert isAuthorizedAfter == isAuthorizedBefore || authorizerIsAuthorized;
}

/// ACCESS CONTROL ///

/// take requires the caller to be the taker or authorized by the taker.
rule unauthorizedTakeFails(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);
    assert !lastReverted => e.msg.sender == taker || isAuthorized(taker, e.msg.sender);
}

/// take with a custom ratifier requires the ratifier to be authorized by the maker.
rule unauthorizedOnRatifyFails(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require offer.ratifier != 0;
    require offer.ratifier != 1;
    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);
    assert !lastReverted => isAuthorized(offer.maker, offer.ratifier);
}

/// ISOLATION ///

/// setIsAuthorized only changes the specified (onBehalf, authorized) pair.
rule setIsAuthorizedIsolation(env e, address onBehalf, address authorized, bool val, address otherUser, address otherAuthorized) {
    require otherUser != onBehalf || otherAuthorized != authorized;

    bool before = isAuthorized(otherUser, otherAuthorized);
    setIsAuthorized(e, onBehalf, authorized, val);
    assert isAuthorized(otherUser, otherAuthorized) == before;
}
