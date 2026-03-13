// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function slash(bytes32 id, address user) internal => slashSummary(id, user);
}

/// GHOSTS ///

persistent ghost mapping(bytes32 => mapping(address => bool)) slashed {
    init_state axiom (forall bytes32 id. forall address user. !slashed[id][user]);
}

function slashSummary(bytes32 id, address user) {
    slashed[id][user] = true;
}

/// HOOKS ///

// Positive balances must only be read after slash.
hook Sload int256 value position[KEY bytes32 id][KEY address user].balance {
    require slashed[id][user] || value <= 0;
}

// Positive balances must only be overwritten after slash.
hook Sstore position[KEY bytes32 id][KEY address user].balance int256 newValue (int256 oldValue) {
    require slashed[id][user] || oldValue <= 0;
}

/// RULES ///

// View functions that read balanceOf don't call slash (they can't mutate state).
rule balanceReadAfterSlash(method f, env e, calldataarg args)
filtered {
    f -> f.selector != sig:balanceOf(bytes32, address).selector
        && f.selector != sig:debtOf(bytes32, address).selector
        && f.selector != sig:balanceOfAfterSlashing(bytes32, address).selector
        && f.selector != sig:isHealthy(Midnight.Obligation, bytes32, address).selector
} {
    f(e, args);
    assert true;
}

rule balanceWrittenAfterSlash(method f, env e, calldataarg args) {
    f(e, args);
    assert true;
}
