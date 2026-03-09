// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32);

    function _.price() external => NONDET;
}

///  Only `setConsumed` and `take` can modify the consumed mapping.
rule onlySetConsumedAndTakeChangeConsumed(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> f.selector != sig:setConsumed(bytes32, uint256, address).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {

    uint256 consumedBefore = consumed(user, group);

    f(e, args);

    assert consumed(user, group) == consumedBefore;
}

/// Calling `setConsumed` only affects msg.sender's consumed value for the given group.
/// No other (user, group) pair is modified.
rule setConsumedOnlyAffectsOnBehalf(env e, bytes32 group, uint256 amount, address onBehalf, address otherUser, bytes32 otherGroup) {
    uint256 otherConsumedBefore = consumed(otherUser, otherGroup);

    setConsumed(e, group, amount, onBehalf);

    // Any pair that is not (onBehalf, group) remains unchanged.
    assert (otherUser != onBehalf || otherGroup != group) => consumed(otherUser, otherGroup) == otherConsumedBefore;
}

/// Calling `take` only affects the maker's consumed value for the offer's group.
/// No other (user, group) pair is modified.
rule takeOnlyAffectsMakerConsumed(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address user, bytes32 group) {
    uint256 consumedBefore = consumed(user, group);

    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    // Any pair that is not exactly (offer.maker, offer.group) must be unchanged.
    assert (user != offer.maker || group != offer.group) => consumed(user, group) == consumedBefore;
}

/// The consumed mapping is non-decreasing: no function can decrease consumed[user][group].
rule consumeNonDecreasing(env e, method f, calldataarg args, address user, bytes32 group) {
    uint256 consumedBefore = consumed(user, group);

    f(e, args);

    assert consumed(user, group) >= consumedBefore;
}

/// After a successful `take`, consumed[offer.maker][offer.group] does not exceed the offer's max amount
/// (offer.obligationUnits if units-based, offer.obligationShares if shares-based).
rule takeConsumedBoundedByMax(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    uint256 maxAmount = offer.obligationUnits > 0 ? offer.obligationUnits : offer.obligationShares;
    assert consumed(offer.maker, offer.group) <= maxAmount;
}

/// If consumed[offer.maker][offer.group] is already at or above the offer's max amount before a `take`,
/// it remains unchanged.
rule takeConsumedAtMaxUnchanged(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);
    uint256 maxAmount = offer.obligationUnits > 0 ? offer.obligationUnits : offer.obligationShares;

    require consumedBefore >= maxAmount;

    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    assert consumed(offer.maker, offer.group) == consumedBefore;
}

/// A fully-consumed offer always reverts when the take input is non-zero in the offer's consumption dimension.
rule fullyConsumedOfferRevertsOnNonTrivialTake(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    bytes32 id = toId(e, offer.obligation);
    uint256 _totalUnits = totalUnits(id);
    uint256 _totalShares = totalShares(id);

    require (offer.obligationUnits > 0 && consumedBefore >= offer.obligationUnits && obligationShares > 0) || (offer.obligationShares > 0 && consumedBefore >= offer.obligationShares && obligationShares > 0);

    // When consumption is units-based, prevent rounding down to 0
    require offer.obligationUnits > 0 => to_mathint(obligationShares) * (to_mathint(_totalUnits) + 1) >= to_mathint(_totalShares) + 1;

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert lastReverted;
}
