// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tradingFee(bytes32 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function maxTradingFee(uint256 index) external returns (uint256) envfree;
    function feeSetter() external returns (address) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;

    // doesn't weaken the invariant but improves verification time
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

definition FEE_STEP() returns mathint = 1000000000000;

/// Breakpoint time in seconds for index 0..6, mirroring the tradingFee intervals in Midnight.sol.
definition breakpointTime(uint256 index) returns uint256 = index == 0 ? 0 : index == 1 ? 86400 : index == 2 ? 604800 : index == 3 ? 2592000 : index == 4 ? 7776000 : index == 5 ? 15552000 : index == 6 ? 31104000 : 0;

/// Lower enclosing breakpoint index for a given time-to-maturity.
definition lowerIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 5 : ttm >= breakpointTime(4) ? 4 : ttm >= breakpointTime(3) ? 3 : ttm >= breakpointTime(2) ? 2 : ttm >= breakpointTime(1) ? 1 : 0;

/// Upper enclosing breakpoint index for a given time-to-maturity.
definition upperIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 6 : ttm >= breakpointTime(4) ? 5 : ttm >= breakpointTime(3) ? 4 : ttm >= breakpointTime(2) ? 3 : ttm >= breakpointTime(1) ? 2 : 1;

/// maxTradingFee(index) / FEE_STEP, needed because contract calls are disallowed inside forall.
definition maxFeeUnits(uint256 index) returns mathint = index == 0 ? 14 : index == 1 ? 14 : index == 2 ? 98 : index == 3 ? 417 : index == 4 ? 1250 : index == 5 ? 2500 : index == 6 ? 5000 : 0;

persistent ghost mapping(bytes32 => mapping(uint256 => mathint)) ghostObligationFeeUnits {
    init_state axiom forall bytes32 id. forall uint256 i. ghostObligationFeeUnits[id][i] == 0;
}

persistent ghost mapping(address => mapping(uint256 => mathint)) ghostDefaultFeeUnits {
    init_state axiom forall address t. forall uint256 i. ghostDefaultFeeUnits[t][i] == 0;
}

hook Sstore obligationState[KEY bytes32 id].fees[INDEX uint256 idx] uint16 newVal {
    ghostObligationFeeUnits[id][idx] = to_mathint(newVal);
}

hook Sload uint16 val obligationState[KEY bytes32 id].fees[INDEX uint256 idx] {
    require ghostObligationFeeUnits[id][idx] == to_mathint(val);
}

hook Sstore defaultFees[KEY address token][INDEX uint256 idx] uint16 newVal {
    ghostDefaultFeeUnits[token][idx] = to_mathint(newVal);
}

hook Sload uint16 val defaultFees[KEY address token][INDEX uint256 idx] {
    require ghostDefaultFeeUnits[token][idx] == to_mathint(val);
}

/// Default fees for any loan token at each index are bounded by its specific maxTradingFee cap.
invariant defaultFeePerIndexBound()
    forall address loanToken. forall uint256 index. index <= 6 => ghostDefaultFeeUnits[loanToken][index] <= maxFeeUnits(index);

/// Every obligation's fee breakpoints are bounded by the per-index maximum.
invariant obligationFeePerIndexBound(bytes32 id, uint256 index)
    index <= 6 => ghostObligationFeeUnits[id][index] <= maxFeeUnits(index);
    {
        preserved with (env e) {
            requireInvariant defaultFeePerIndexBound();
        }
    }

/// Only the fee setter can modify default fees (multicall is DELETEd and not checked here).
rule onlyFeeSetterCanChangeDefaultFees(method f, env e, address token, uint256 index) filtered { f -> !f.isView } {
    mathint feesBefore = ghostDefaultFeeUnits[token][index];

    calldataarg args;
    f(e, args);

    assert ghostDefaultFeeUnits[token][index] != feesBefore => e.msg.sender == feeSetter();
}

/// Once an obligation is created, only the fee setter can modify its fees.
rule onlyFeeSetterCanChangeObligationFeesPostCreation(method f, env e, bytes32 id, uint256 index) filtered { f -> !f.isView } {
    require obligationCreated(id);
    mathint feesBefore = ghostObligationFeeUnits[id][index];

    calldataarg args;
    f(e, args);

    assert ghostObligationFeeUnits[id][index] != feesBefore => e.msg.sender == feeSetter() && f.selector == sig:setObligationTradingFee(bytes32, uint256, uint256).selector;
}

/// For any time-to-maturity the trading fee is enclosed between the two adjacent breakpoint values (never overshoots or undershoots).
rule tradingFeeIsConvexCombination(bytes32 id, uint256 timeToMaturity) {
    uint256 feeLo = tradingFee(id, breakpointTime(lowerIndex(timeToMaturity)));
    uint256 feeHi = tradingFee(id, breakpointTime(upperIndex(timeToMaturity)));
    uint256 fee = tradingFee(id, timeToMaturity);

    assert (feeLo <= feeHi) => (fee >= feeLo && fee <= feeHi);
    assert (feeHi <= feeLo) => (fee >= feeHi && fee <= feeLo);
}
