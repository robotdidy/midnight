// SPDX-License-Identifier: GPL-2.0-or-later

using Havoc as callback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateralOf(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;

    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address morpho) internal returns (bytes32) => summaryToId(obligation, chainId, morpho);
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function _.havocAll() external => HAVOC_ALL;

    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.onBuy(Midnight.Obligation obligation, address buyer, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, bytes data) external => genericCallback() expect void;
    function _.onSell(Midnight.Obligation obligation, address seller, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, bytes data) external => genericCallback() expect void;
    function _.onLiquidate(Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallback() expect void;
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => genericCallback() expect void;
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint {
    /* mulDiv always returns an unsigned integer */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivDownM(a, b, d) >= 0;

    /* proved in mulDivZero in MulDiv.spec */
    axiom forall mathint b. forall mathint d. d > 0 => summaryMulDivDownM(0, b, d) == 0;

    /* proved in mulDivMonotoneA in MulDiv.spec */
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 => summaryMulDivDownM(a1, b, d) <= summaryMulDivDownM(a2, b, d);

    /* proved in mulDivMonotoneB in MulDiv.spec */
    axiom forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. d > 0 && b1 <= b2 => summaryMulDivDownM(a, b1, d) <= summaryMulDivDownM(a, b2, d);
}

persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint {
    /* mulDiv always returns an unsigned integer */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) >= 0;

    /* proved in mulDivMonotoneA in MulDiv.spec */
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 => summaryMulDivUpM(a1, b, d) <= summaryMulDivUpM(a2, b, d);

    /* proved in mulDivMonotoneD in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. d1 > 0 && d1 <= d2 => summaryMulDivUpM(a, b, d1) >= summaryMulDivUpM(a, b, d2);
}

/* Axioms that are proved by MulDiv.spec */

/* proved in mulDivAddDownUp in MulDiv.spec */
definition axiomAddDownUp(mathint a1, mathint a2, mathint b, mathint d) returns bool = d > 0 => summaryMulDivDownM(a1, b, d) + summaryMulDivUpM(a2, b, d) >= summaryMulDivDownM(a1 + a2, b, d);

/* proved in mulDivInverseUpDown in MulDiv.spec */
definition axiomInverseUpDown(mathint a, mathint b, mathint d) returns bool = b > 0 && d > 0 => summaryMulDivUpM(summaryMulDivDownM(a, b, d), d, b) <= a;

/* proved in mulDivLifLLTV in MulDiv.spec */
definition axiomLifLLTV(mathint a, mathint lif, mathint lltv) returns bool = lltv * lif < WAD() * WAD() => summaryMulDivUpM(a, lltv, WAD()) <= summaryMulDivUpM(a, WAD(), lif);

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivDownM(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivUpM(a, b, d));
}

// global variable to track whether the user was healthy before the callbacks.
persistent ghost bool healthyBeforeCallback;

// global variable to track which obligation and borrower we're testing.
persistent ghost address globalObligationLoanToken;

persistent ghost uint256 globalObligationCollateralLength;

persistent ghost mapping(uint256 => address) globalObligationCollateralOracle;

persistent ghost mapping(uint256 => address) globalObligationCollateralToken;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralLLTV;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralMaxLif;

persistent ghost bytes32 globalId;

persistent ghost address globalBorrower;

// helper function to check if one of the collaterals of an obligation matches the global variables.
// It checks for the length and also returns true if the index is out of bounds. This allows us to require this for every index.
definition collateralMatches(Midnight.Obligation obligation, uint256 index) returns bool = (index < globalObligationCollateralLength => obligation.collaterals[index].oracle == globalObligationCollateralOracle[index] && obligation.collaterals[index].token == globalObligationCollateralToken[index] && obligation.collaterals[index].lltv == globalObligationCollateralLLTV[index] && obligation.collaterals[index].maxLif == globalObligationCollateralMaxLif[index]);

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address morpho) returns (bytes32) {
    bytes32 id;
    if (
        obligation.loanToken == globalObligationLoanToken
            && obligation.collaterals.length == globalObligationCollateralLength
            && collateralMatches(obligation, 0)
            && collateralMatches(obligation, 1)
            && collateralMatches(obligation, 2)
            && morpho == currentContract
    ) {
        require id == globalId;
    } else {
        require id != globalId;
    }
    return id;
}

function genericCallback() {
    address dummy;
    env e;
    Midnight.Obligation obligation;

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    require collateralMatches(obligation, 1);
    require collateralMatches(obligation, 2);

    if (!isHealthy(obligation, globalId, globalBorrower)) {
        healthyBeforeCallback = false;
    }

    callback.callHavoc(e, dummy);

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy after callback";
}

function genericCallbackBool() returns (bool) {
    bool result;

    genericCallback();
    return result;
}

rule stayHealthyLiquidateSameBorrower(env e, uint256 someCollateralIndex, uint256 someSeizedAssets, uint256 someRepaidUnits, bytes someData) {
    Midnight.Obligation obligation;

    // reset the ghost variable that tracks whether the user was healthy before the callbacks.
    healthyBeforeCallback = true;

    require globalObligationCollateralLLTV[someCollateralIndex] * globalObligationCollateralMaxLif[someCollateralIndex] < WAD() * WAD(), "collateral lltv must be less then 1/maxLif";

    require globalObligationCollateralLength <= 1, "too many collaterals for the spec to handle";

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    // require collateralMatches(obligation, 1);
    // require collateralMatches(obligation, 2);

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy before call";

    uint256 collateralBefore = collateralOf(globalId, globalBorrower, someCollateralIndex);
    uint256 seizedAssets;
    uint256 repaidUnits;

    seizedAssets, repaidUnits = liquidate(e, obligation, someCollateralIndex, someSeizedAssets, someRepaidUnits, globalBorrower, someData);

    // we cannot use collateralOf, as it may already have been changed by the callbacks.
    mathint collateralAfter = collateralBefore - seizedAssets;
    mathint price = summaryPrice(obligation.collaterals[someCollateralIndex].oracle);

    // require all the axioms that are needed to prove the healthiness after liquidation. These are the same axioms that are proved in the MulDiv.spec
    require axiomInverseUpDown(repaidUnits, globalObligationCollateralMaxLif[someCollateralIndex], WAD()), "axiom";
    require axiomInverseUpDown(summaryMulDivDownM(repaidUnits, globalObligationCollateralMaxLif[someCollateralIndex], WAD()), ORACLE_PRICE_SCALE(), price), "axiom";
    require axiomLifLLTV(summaryMulDivUpM(seizedAssets, price, ORACLE_PRICE_SCALE()), globalObligationCollateralMaxLif[someCollateralIndex], globalObligationCollateralLLTV[someCollateralIndex]);
    require axiomAddDownUp(collateralAfter, seizedAssets, price, ORACLE_PRICE_SCALE()), "axiom";
    require axiomAddDownUp(summaryMulDivDownM(collateralAfter, price, ORACLE_PRICE_SCALE()), summaryMulDivUpM(seizedAssets, price, ORACLE_PRICE_SCALE()), globalObligationCollateralLLTV[someCollateralIndex], WAD()), "axiom";

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert isHealthy(obligation, globalId, globalBorrower), "user is healthy after call";
}

rule stayHealthyLiquidateOtherBorrower(env e, Midnight.Obligation someObligation, uint256 someCollateralIndex, uint256 someSeizedAssets, uint256 someRepaidUnits, address someBorrower, bytes someData) {
    Midnight.Obligation obligation;

    // reset the ghost variable that tracks whether the user was healthy before the callbacks.
    healthyBeforeCallback = true;

    require globalObligationCollateralLength <= 1, "too many collaterals for the spec to handle";

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    // require collateralMatches(obligation, 1);
    // require collateralMatches(obligation, 2);

    require someBorrower != globalBorrower || someObligation.loanToken != globalObligationLoanToken || someObligation.collaterals.length != globalObligationCollateralLength || !collateralMatches(someObligation, 0) || !collateralMatches(someObligation, 1) || !collateralMatches(someObligation, 2), "either user or obligation in the liquidation call is different";

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy before call";

    uint256 seizedAssets;
    uint256 repaidUnits;

    seizedAssets, repaidUnits = liquidate(e, someObligation, someCollateralIndex, someSeizedAssets, someRepaidUnits, someBorrower, someData);

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert isHealthy(obligation, globalId, globalBorrower), "user is healthy after call";
}

rule stayHealthy(env e, method f, calldataarg args) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    Midnight.Obligation obligation;

    // reset the ghost variable that tracks whether the user was healthy before the callbacks.
    healthyBeforeCallback = true;

    require globalObligationCollateralLength <= 3, "too many collaterals for the spec to handle";

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    require collateralMatches(obligation, 1);
    require collateralMatches(obligation, 2);

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy before call";

    f(e, args);

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert isHealthy(obligation, globalId, globalBorrower), "user is healthy after call";
}
