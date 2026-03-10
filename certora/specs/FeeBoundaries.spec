// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tradingFee(bytes32 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function maxTradingFee(uint256 index) external returns (uint256) envfree;
    function feeSetter() external returns (address) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;

    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

/// Breakpoint times in seconds
definition T_0D() returns uint256 = 0;

definition T_1D() returns uint256 = 86400;

definition T_7D() returns uint256 = 604800;

definition T_30D() returns uint256 = 2592000;

definition T_90D() returns uint256 = 7776000;

definition T_180D() returns uint256 = 15552000;

definition T_360D() returns uint256 = 31104000;

/// Stored fee units corresponding to maxTradingFee(index) / FEE_STEP.
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
invariant defaultFeePerIndexBound(address loanToken, uint256 index)
    index <= 6 => ghostDefaultFeeUnits[loanToken][index] <= maxFeeUnits(index);

/// Every obligation's fee breakpoints are bounded by the per-index maximum.
invariant obligationFeePerIndexBound(bytes32 id, uint256 index)
    index <= 6 => ghostObligationFeeUnits[id][index] <= maxFeeUnits(index)
    {
        preserved with (env e) {
            require forall address t. forall uint256 i. i <= 6 => ghostDefaultFeeUnits[t][i] <= maxFeeUnits(i);
        }
    }

/// If all fee breakpoints are zero in storage, the trading fee is zero everywhere.
rule zeroFeesImplyZeroTradingFee(bytes32 id, uint256 timeToMaturity) {
    require forall uint256 i. i <= 6 => ghostObligationFeeUnits[id][i] == 0;

    assert tradingFee(id, timeToMaturity) == 0;
}

/// The interpolated fee never exceeds any upper bound that all breakpoint values satisfy.
rule tradingFeeBoundedByBreakpoints(bytes32 id, uint256 timeToMaturity, uint256 upperBound) {
    require tradingFee(id, T_0D()) <= upperBound;
    require tradingFee(id, T_1D()) <= upperBound;
    require tradingFee(id, T_7D()) <= upperBound;
    require tradingFee(id, T_30D()) <= upperBound;
    require tradingFee(id, T_90D()) <= upperBound;
    require tradingFee(id, T_180D()) <= upperBound;
    require tradingFee(id, T_360D()) <= upperBound;

    assert tradingFee(id, timeToMaturity) <= upperBound;
}

/// The interpolated fee never drops below any lower bound that all breakpoint values satisfy.
rule tradingFeeLowerBoundedByBreakpoints(bytes32 id, uint256 timeToMaturity, uint256 lowerBound) {
    require tradingFee(id, T_0D()) >= lowerBound;
    require tradingFee(id, T_1D()) >= lowerBound;
    require tradingFee(id, T_7D()) >= lowerBound;
    require tradingFee(id, T_30D()) >= lowerBound;
    require tradingFee(id, T_90D()) >= lowerBound;
    require tradingFee(id, T_180D()) >= lowerBound;
    require tradingFee(id, T_360D()) >= lowerBound;

    assert tradingFee(id, timeToMaturity) >= lowerBound;
}

/// For TTM >= 360 days, the trading fee is constant.s
rule flatFeeAbove360Days(bytes32 id, uint256 t1, uint256 t2) {
    require t1 >= T_360D();
    require t2 >= T_360D();

    assert tradingFee(id, t1) == tradingFee(id, t2);
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

    assert ghostObligationFeeUnits[id][index] != feesBefore => e.msg.sender == feeSetter();
}
