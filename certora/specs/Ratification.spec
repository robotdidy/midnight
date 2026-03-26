// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function ratified(address user, bytes32 root) external returns (bool) envfree;
    function ECRECOVER_RATIFIER() external returns (address) envfree;

    function _.price() external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes32[], bytes) external => NONDET;
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;

    // Summaries for internals irrelevant to ratification properties.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function Midnight.isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

}

/// Every successful take requires maker consent: either the ecrecover ratifier is used, or the maker authorized the ratifier.
rule takeRequiresMakerConsent(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    address ecrecoverRatifier = ECRECOVER_RATIFIER();
    bool makerAuthorizedRatifier = isAuthorized(offer.maker, offer.ratifier);

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert offer.ratifier == ecrecoverRatifier || makerAuthorizedRatifier;
}

/// No successful take can use address(0) as maker.
rule takeRequiresNonZeroMaker(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);
    assert !lastReverted => offer.maker != 0;
}

/// ISOLATION ///

/// setAuthorizedWithSig only changes isAuthorized for the (authorizer, authorizee) in the authorization struct.
rule setAuthorizedWithSigIsolation(env e, Midnight.Authorization authorization, Midnight.Signature signature, address otherUser, address otherAuthorized) {
    require otherUser != authorization.authorizer || otherAuthorized != authorization.authorizee;

    bool before = isAuthorized(otherUser, otherAuthorized);
    setAuthorizedWithSig(e, authorization, signature);
    assert isAuthorized(otherUser, otherAuthorized) == before;
}

/// setRatified only changes the specified (onBehalf, root) pair.
rule setRatifiedIsolation(env e, address onBehalf, bytes32 root, bool val, address otherUser, bytes32 otherRoot) {
    require otherUser != onBehalf || otherRoot != root;

    bool before = ratified(otherUser, otherRoot);
    setRatified(e, onBehalf, root, val);
    assert ratified(otherUser, otherRoot) == before;
}
