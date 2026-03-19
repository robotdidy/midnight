// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that no division by zero occurs in mulDivDown or mulDivUp.
//
// All other Solidity divisions in the codebase use constant denominators:
// - tradingFee: divides by (end - start), always a positive constant from the breakpoint table.
// - setObligationTradingFee / setDefaultTradingFee: divide by FEE_STEP (1e12).
// - liquidate: divides by TIME_TO_MAX_LIF (15 minutes = 900).
//
// Therefore, only mulDivDown and mulDivUp can have variable denominators.
//
// PROVEN ELSEWHERE (used here as summaries since mulDivDown is NONDET in this spec):
//
// P1. maxLif(lltv, cursor) >= WAD:
//     Proven in ExactMath.spec (rule maxLifIsAtLeastWad) using the real mulDivDown implementation.
//     This matters for touchObligation which calls maxLif internally; it ensures the nested
//     mulDivDown divisor WAD - cursor*(WAD-lltv)/WAD is positive (via the bounded summary).
//
// P2. Bounded mulDiv summaries:
//     mulDivDown(x, y, d) <= x when y <= d (algebraically true: x*y/d <= x*d/d = x).
//     mulDivUp(x, y, d) <= x when y <= d (algebraically true: ceil(x*y/d) <= ceil(x*d/d) = x).
//     These are mathematical facts about floor/ceil division, not protocol assumptions.
//
// ASSUMPTIONS (unproven, but justified):
//
// A1. lossIndex < type(uint128).max:
//     The contract acknowledges that "if an obligation loses more than 99%+ of its value to bad debt
//     over its lifetime, it won't function properly afterwards (bad debt can no longer be realized)."
//     We formalize this as: lossIndex never reaches type(uint128).max (100% loss).
//
// A2. Oracle prices are non-zero.
//     A zero oracle price is meaningless and would break all collateral valuations.
//
// EXCLUSIONS:
//
// - maxLif(uint256, uint256): Excluded because it is a public pure function callable with arbitrary
//   inputs. In practice it is only called from touchObligation with cursor in {0.25e18, 0.5e18},
//   which guarantees the inner divisor WAD - cursor*(WAD-lltv)/WAD > 0. A standalone call with
//   cursor >= WAD could cause a division by zero, but this would simply revert (Solidity 0.8
//   checked arithmetic). No state change occurs.
//
// - liquidate: Excluded because it requires a combination of precise summaries that NONDET cannot
//   provide. Specifically:
//   (a) UtilsLib.msb is NONDET, so the prover can construct paths where the liquidated collateral
//       index is not visited in the bitmap loop, leaving liquidatedCollatPrice = 0. In reality,
//       msb returns the MSB of the bitmap, ensuring all activated collateral indices are visited.
//       Calling liquidate on an inactive collateral index is an invalid input that reverts via
//       Solidity's checked arithmetic (division by zero or underflow).
//   (b) IdLib.toId is NONDET, so the prover cannot infer that calldata obligation fields match the
//       stored obligation. In reality, toId is a deterministic hash, so different obligation content
//       produces different ids.
//   (c) The recovery close factor divisor WAD - ceil(lif*lltv/WAD) requires proving that
//       lif*lltv < WAD^2, which depends on the maxLif formula and involves nonlinear arithmetic.
//   Verifying liquidate's division safety would require either inlining mulDiv (causing timeouts)
//   or providing ghost-backed summaries with algebraic axioms (similar to the stayHealthy approach
//   in PR #388).

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // A2: oracle prices are non-zero.
    function _.price() external => nonZeroPrice() expect(uint256);

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Hook mulDivDown and mulDivUp to track division by zero.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);

    // P1: maxLif >= WAD (proven in ExactMath.spec, rule maxLifIsAtLeastWad).
    function Midnight.maxLif(uint256 lltv, uint256 cursor) internal returns (uint256) => maxLifSummary(lltv);
}

/// GHOSTS ///

// Persistent so the flag survives havoc from external calls (callbacks).
persistent ghost bool divisionByZero {
    init_state axiom !divisionByZero;
}

/// HOOKS ///

// A1: lossIndex never reaches type(uint128).max.
hook Sload uint128 value obligationState[KEY bytes32 id].lossIndex {
    require value < max_uint128;
}

hook Sload uint128 value position[KEY bytes32 id][KEY address user].lossIndex {
    require value < max_uint128;
}

/// SUMMARIES ///

function nonZeroPrice() returns uint256 {
    uint256 price;
    require price > 0;
    return price;
}

definition WAD() returns uint256 = 1000000000000000000;

// P1: maxLif >= WAD (proven in ExactMath.spec, rule maxLifIsAtLeastWad).
function maxLifSummary(uint256 lltv) returns uint256 {
    uint256 result;
    require result >= WAD();
    return result;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        divisionByZero = true;
    }
    uint256 result;

    // P2: Sound bound from the definition mulDivDown(x,y,d) = floor(x*y/d).
    // When y <= d and d > 0: x*y/d <= x*d/d = x, so result <= x.
    // Symmetric: when x <= d and d > 0: x*y/d <= d*y/d = y, so result <= y.
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;
    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        divisionByZero = true;
    }
    uint256 result;

    // P2: Sound bound from the definition mulDivUp(x,y,d) = ceil(x*y/d).
    // When y <= d and d > 0: ceil(x*y/d) <= ceil(x*d/d) = x, so result <= x.
    // Symmetric for x <= d.
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;
    return result;
}

/// RULES ///

// Exclude maxLif and liquidate (see EXCLUSIONS above).
rule noDivisionByZero(method f, env e, calldataarg args) filtered { f -> f.selector != sig:maxLif(uint256, uint256).selector && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    require !divisionByZero;
    f(e, args);
    assert !divisionByZero, "division by zero detected in mulDivDown or mulDivUp";
}
