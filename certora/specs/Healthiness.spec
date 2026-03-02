// SPDX-License-Identifier: GPL-2.0-or-later

using Havoc as callback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes20 id) external returns (uint256) envfree;
    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(bytes20 id, address owner) external returns (uint256) envfree;
    function collateralOf(bytes20 id, address user, uint256) external returns (uint128) envfree;
    function debtOf(bytes20 id, address user) external returns (uint256) envfree;
    function isHealthy(Midnight.Obligation, bytes20, address) external returns (bool) envfree;
    function preciseMaxDebt(address borrower, Midnight.Obligation obligation, bytes20 id) external returns (uint256) envfree;

    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address morpho) internal returns (bytes20) => summaryToId(obligation, chainId, morpho);
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function _.havocAll() external => HAVOC_ALL;

    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect (bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect (bool);
    function _.onBuy(Midnight.Obligation obligation, address buyer, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, bytes data) external => genericCallback() expect void;
    function _.onSell(Midnight.Obligation obligation, address seller, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, bytes data) external => genericCallback() expect void;
    function _.onLiquidate(Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallback() expect void;
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => genericCallback() expect void;
}

/// SUMMARY ///

definition MAX_LIF() returns uint256 = 115 * 10^16;
definition WAD() returns uint256 = 10^18;

persistent ghost summaryPrice(address) returns uint256;
persistent ghost summaryMulDivDownM(mathint,mathint,mathint) returns mathint {
    axiom forall mathint b. forall mathint d. d > 0 =>
        summaryMulDivDownM(0, b, d) == 0;
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
        summaryMulDivDownM(a1, b, d) <= summaryMulDivDownM(a2, b, d);
//    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
//        summaryMulDivDownM(a2 - a1, b, d) <= summaryMulDivDownM(a2, b, d) - summaryMulDivDownM(a1, b, d);
}
persistent ghost summaryMulDivUpM(mathint,mathint,mathint) returns mathint {
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
        summaryMulDivUpM(a1, b, d) <= summaryMulDivUpM(a2, b, d);
//    axiom forall mathint a. forall mathint b. forall mathint d. forall mathint x. b > 0 && d > 0 =>
//        a <= summaryMulDivDownM(summaryMulDivUpM(a, b, d), d, b);
//    axiom forall mathint a. forall mathint b. forall mathint d. forall mathint x. b > 0 && d > 0 =>
//        a >= summaryMulDivUpM(summaryMulDivDownM(a, b, d), d, b);

//    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
//        summaryMulDivDownM(a2 - a1, b, d) >= summaryMulDivDownM(a2, b, d) - summaryMulDivUpM(a1, b, d);
}

definition mulUpAxioms(mathint a, mathint b, mathint d) returns bool =
    a <= summaryMulDivDownM(summaryMulDivUpM(a, b, d), d, b) &&
    summaryMulDivDownM(a,b,d) <= summaryMulDivUpM(a,b,d) &&
    (forall mathint a2. a <= a2 =>
       summaryMulDivDownM(a2 - a, b, d) >= summaryMulDivDownM(a2, b, d) - summaryMulDivUpM(a, b, d)) &&
    (forall mathint a2. summaryMulDivDownM(a2, b, d) >= a => a2 >= summaryMulDivUpM(a, d, b));

definition mulDownAxioms(mathint a, mathint b, mathint d) returns bool =
    summaryMulDivUpM(summaryMulDivDownM(a, b, d), d, b) <= a &&
    (forall mathint a1. forall mathint a2. 
       a1 + summaryMulDivDownM(a, b, d) <= a2  =>
       summaryMulDivDownM(a1, d, b) >= summaryMulDivDownM(a2, d, b) - a);

ghost mapping(mathint => mathint) ghost_MulDivA;
ghost mapping(mathint => mathint) ghost_MulDivB;
ghost mapping(mathint => mathint) ghost_MulDivD;
ghost mathint counter;
ghost uint256 globalCollateralIndex;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    ghost_MulDivA[counter] = a;
    ghost_MulDivB[counter] = b;
    ghost_MulDivD[counter] = d;
    counter = counter + 1;
    require summaryMulDivUpM(a, WAD(), MAX_LIF())  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[globalCollateralIndex], WAD()), "collateral lltv must be less then 1/MAX_LIF";
    //require mulDownAxioms(a,b,d);
    return require_uint256(summaryMulDivDownM(a, b, d));
//    return require_uint256(a * b / d);
}
function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    ghost_MulDivA[counter] = a;
    ghost_MulDivB[counter] = b;
    ghost_MulDivD[counter] = d;
    counter = counter + 1;
    require mulUpAxioms(a,b,d);
    return require_uint256(summaryMulDivUpM(a, b, d));
//    return require_uint256(a * b / d);
}


//persistent ghost Midnight.Obligation globalObligation;
persistent ghost address globalObligationLoanToken;
persistent ghost uint256 globalObligationCollateralLength;
persistent ghost mapping(uint256 => address) globalObligationCollateralOracle;
persistent ghost mapping(uint256 => address) globalObligationCollateralToken;
persistent ghost mapping(uint256 => uint256) globalObligationCollateralLLTV;
persistent ghost bytes20 globalId;
persistent ghost address globalBorrower;

definition collateralMatches(Midnight.Obligation obligation, uint256 index) returns bool =
    (index < globalObligationCollateralLength => 
    obligation.collaterals[index].oracle == globalObligationCollateralOracle[index]
    && obligation.collaterals[index].token == globalObligationCollateralToken[index]
    && obligation.collaterals[index].lltv == globalObligationCollateralLLTV[index]);

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address morpho) returns (bytes20) {
    bytes20 id;
    if (obligation.loanToken == globalObligationLoanToken
        && obligation.collaterals.length == globalObligationCollateralLength
        && collateralMatches(obligation, 0)
        && collateralMatches(obligation, 1)
        && collateralMatches(obligation, 2)
        && collateralMatches(obligation, 3)
        && morpho == currentContract) {
        require id == globalId;
    } else {
        require id != globalId;
    }
    return id;
}

ghost bool globalViolated;

function genericCallback() {
    address dummy;
    env e;
    Midnight.Obligation obligation;

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    require collateralMatches(obligation, 1);
    require collateralMatches(obligation, 2);
    require collateralMatches(obligation, 3);

//    assert preciseMaxDebt(globalBorrower, obligation, globalId) >= debtOf(globalId, globalBorrower), "user is healthy before callback";
    if (!isHealthy(obligation, globalId, globalBorrower)) {
        globalViolated = true;
    }//, "user is healthy before callback";

    callback.callHavoc(e, dummy);

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy after callback";
//    require preciseMaxDebt(globalBorrower, obligation, globalId) >= debtOf(globalId, globalBorrower), "user is healthy after callback";
}

function genericCallbackBool() returns (bool) {
    bool result;

    genericCallback();
    return result;
}

rule stayHealthyLiquidate(env e, Midnight.Obligation someObligation, uint256 someCollateralIndex, uint256 someSeizedAssets, uint256 someRepaidUnits, bytes someData) {
    Midnight.Obligation obligation;

    globalViolated = false;
    counter = 0;
    require forall uint256 a. forall uint256 lif. 
        summaryMulDivUpM(a, WAD(), MAX_LIF())  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[someCollateralIndex], WAD()),
        "collateral lltv must be less then 1/MAX_LIF";

    // require forall uint256 i. forall uint256 a. forall uint256 lif. 
    //     0 <= i && i < globalObligationCollateralLength && lif <= MAX_LIF() =>
    //     summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[i], WAD()),
    //     "collateral lltv must be less then 1/MAX_LIF";

//    require forall uint256 i. 0 <= i && i < globalObligationCollateralLength =>
//        obligation.collaterals[i].lltv * MAX_LIF()  < WAD()*WAD(), "collateral lltv must be less then 1/MAX_LIF";

    require globalObligationCollateralLength <= 4, "too many collaterals for the spec to handle";

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    require collateralMatches(obligation, 1);
    require collateralMatches(obligation, 2);
    require collateralMatches(obligation, 3);

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy before call";
    //require preciseMaxDebt(globalBorrower, obligation, globalId) >= debtOf(globalId, globalBorrower), "user is healthy before call";

    globalCollateralIndex = someCollateralIndex;
    uint256 collateralBefore = collateralOf(globalId, globalBorrower, someCollateralIndex);
    uint256 seizedAssets;
    uint256 repaidUnits;

    seizedAssets, repaidUnits = liquidate(e, someObligation, someCollateralIndex, someSeizedAssets, someRepaidUnits, globalBorrower, someData);

    require summaryMulDivUpM(seizedAssets, WAD(), MAX_LIF())  >= summaryMulDivUpM(seizedAssets, globalObligationCollateralLLTV[someCollateralIndex], WAD()), "collateral lltv must be less then 1/MAX_LIF";
    require summaryMulDivDownM(collateralBefore - seizedAssets, WAD(), MAX_LIF()) >= summaryMulDivDownM(collateralBefore, WAD(), MAX_LIF()) - summaryMulDivUpM(seizedAssets, WAD(), MAX_LIF()), "axiom";

    // if (f.selector == sig:liquidate(Midnight.Obligation,uint256,uint256,uint256,address,bytes).selector) {
    // }
    assert !globalViolated, "user is healthy after call";
    assert isHealthy(obligation, globalId, globalBorrower), "user is healthy after call";
    //assert preciseMaxDebt(globalBorrower, obligation, globalId) >= debtOf(globalId, globalBorrower), "user is healthy after call";
}


rule stayHealthy(env e, method f, calldataarg args) {
    Midnight.Obligation obligation;

    counter = 0;
    require forall uint256 a. forall uint256 lif. 
        summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[0], WAD()),
        "collateral lltv must be less then 1/MAX_LIF";
    require forall uint256 a. forall uint256 lif. 
        summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[1], WAD()),
        "collateral lltv must be less then 1/MAX_LIF";
    require forall uint256 a. forall uint256 lif. 
        summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[2], WAD()),
        "collateral lltv must be less then 1/MAX_LIF";
    require forall uint256 a. forall uint256 lif. 
        summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[3], WAD()),
        "collateral lltv must be less then 1/MAX_LIF";
    // require forall uint256 i. forall uint256 a. forall uint256 lif. 
    //     0 <= i && i < globalObligationCollateralLength && lif <= MAX_LIF() =>
    //     summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, globalObligationCollateralLLTV[i], WAD()),
    //     "collateral lltv must be less then 1/MAX_LIF";

//    require forall uint256 i. 0 <= i && i < globalObligationCollateralLength =>
//        obligation.collaterals[i].lltv * MAX_LIF()  < WAD()*WAD(), "collateral lltv must be less then 1/MAX_LIF";

    require globalObligationCollateralLength <= 4, "too many collaterals for the spec to handle";

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require collateralMatches(obligation, 0);
    require collateralMatches(obligation, 1);
    require collateralMatches(obligation, 2);
    require collateralMatches(obligation, 3);

    require isHealthy(obligation, globalId, globalBorrower), "user is healthy before call";
    //require preciseMaxDebt(globalBorrower, obligation, globalId) >= debtOf(globalId, globalBorrower), "user is healthy before call";

    f(e, args);

    // if (f.selector == sig:liquidate(Midnight.Obligation,uint256,uint256,uint256,address,bytes).selector) {
    // }
    assert isHealthy(obligation, globalId, globalBorrower), "user is healthy after call";
    //assert preciseMaxDebt(globalBorrower, obligation, globalId) >= debtOf(globalId, globalBorrower), "user is healthy after call";
}
