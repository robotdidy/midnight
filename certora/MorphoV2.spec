// SPDX-License-Identifier: GPL-2.0-or-later

/// METHODS ///

methods {
    function withdrawable(bytes32 id) external returns uint256 envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function sharesOf(address owner, bytes32 id) external returns (uint256) envfree;
    function debtOf(address owner, bytes32 id) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function _.price() external => NONDET;
}

/// HELPERS ///

persistent ghost mapping(bytes32 => mathint) sumSharesOf {
    init_state axiom (forall bytes32 id. sumSharesOf[id] == 0);
}
hook Sload uint256 sharesOfOwner sharesOf[KEY address owner][KEY bytes32 id] {
    require sumSharesOf[id] >= to_mathint(sharesOfOwner);
}
hook Sstore sharesOf[KEY address owner][KEY bytes32 id] uint256 newShares (uint256 oldShares) {
    sumSharesOf[id] = sumSharesOf[id] - oldShares + newShares;
}

persistent ghost mapping(bytes32 => mathint) sumDebtOf {
    init_state axiom (forall bytes32 id. sumDebtOf[id] == 0);
}
hook Sload uint256 debtOfOwner debtOf[KEY address owner][KEY bytes32 id] {
    require sumDebtOf[id] >= to_mathint(debtOfOwner);
}
hook Sstore debtOf[KEY address owner][KEY bytes32 id] uint256 newDebt (uint256 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

/// SANITY ///

rule sanity() {
    assert true;
}

/// INVARIANTS ///

strong invariant totalUnitsEqualsSumDebtPlusWithdrawable(bytes32 id)
    totalUnits(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumSharesOf(bytes32 id)
    totalShares(id) == sumSharesOf[id];

// this is not true because of the roundings in shares to/from assets conversions
// strong invariant sharePriceBelow1(bytes32 id)
//     totalShares(id) >= totalUnits(id);

// this is not true because of the roundings in shares to/from assets conversions
// invariant notBorrowerAndLender(bytes32 id, address user)
//     sharesOf(user, id) == 0 || debtOf(user, id) == 0;
