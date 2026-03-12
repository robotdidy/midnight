// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(bytes32 id, address owner) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function lastContinuousFeeAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 x, address y) internal returns (bytes32) => summaryToId(obligation, x, y);

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

/// HELPERS ///

persistent ghost mapping(bytes32 => uint256) ghostMaturity {
    init_state axiom (forall bytes32 id. ghostMaturity[id] == 0);
}

function summaryToId(Midnight.Obligation obligation, uint256 x, address y) returns bytes32 {
    bytes32 id;
    require ghostMaturity[id] == obligation.maturity;
    return id;
}

persistent ghost mapping(bytes32 => mathint) sumSharesOf {
    init_state axiom (forall bytes32 id. sumSharesOf[id] == 0);
}

hook Sstore sharesOf[KEY bytes32 id][KEY address owner] uint256 newShares (uint256 oldShares) {
    sumSharesOf[id] = sumSharesOf[id] - oldShares + newShares;
}

persistent ghost mapping(bytes32 => mathint) sumDebtOf {
    init_state axiom (forall bytes32 id. sumDebtOf[id] == 0);
}

hook Sstore borrowerState[KEY bytes32 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    return res;
}

definition isPassiveFeeRecipient(address user) returns bool = user == Utils.passiveFeeRecipient();

rule takeInputOutputConsistency(env e, uint256 obligationSharesInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, obligationSharesInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    // The output obligationShares is equal to the input.
    assert obligationSharesOutput == obligationSharesInput;

    // If the input is zero, all the output arguments are zero.
    assert obligationSharesInput == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0 && obligationUnitsOutput == 0 && obligationSharesOutput == 0;
}

rule offerInputsConsumed(env e, uint256 obligationSharesInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, obligationSharesInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    if (offer.obligationUnits > 0) {
        assert consumed(offer.maker, offer.group) == consumedBefore + obligationUnitsOutput;
    } else {
        assert consumed(offer.maker, offer.group) == consumedBefore + obligationSharesOutput;
    }
}

rule offerInputsLimit(env e, uint256 obligationSharesInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    take(e, obligationSharesInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    if (offer.obligationUnits > 0) {
        assert consumed(offer.maker, offer.group) <= offer.obligationUnits;
    } else {
        assert consumed(offer.maker, offer.group) <= offer.obligationShares;
    }
}

rule liquidateInputOutputConsistency(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    uint256 seizedAssetsOutput;
    uint256 repaidUnitsOutput;

    seizedAssetsOutput, repaidUnitsOutput = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // At most one of the input arguments can be zero.
    assert seizedAssets == 0 || repaidUnits == 0;

    // The output arguments are equal to the input arguments if the input arguments are non-zero.
    assert seizedAssets == 0 || seizedAssetsOutput == seizedAssets;
    assert repaidUnits == 0 || repaidUnitsOutput == repaidUnits;

    // If all the input arguments are zero, all the output arguments are zero.
    assert repaidUnits == 0 && seizedAssets == 0 => seizedAssetsOutput == 0 && repaidUnitsOutput == 0;
}

rule debtIncreaseUpdatesLastAccrual(env e, method f, calldataarg args, bytes32 id, address user) filtered {
    f ->
        f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector ||
        f.selector == sig:repay(Midnight.Obligation, uint256, address).selector ||
        f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector ||
        f.selector == sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
} {
    uint256 debtBefore = debtOf(id, user);

    require e.block.timestamp < 2 ^ 128;

    f(e, args);

    // If debt increased (from fee accrual or new borrowing), lastAccrual is current timestamp.
    assert debtOf(id, user) > debtBefore => lastContinuousFeeAccrual(id, user) == assert_uint128(e.block.timestamp);
}

rule lastAccrualMonotonicity(env e, method f, calldataarg args, bytes32 id, address user) filtered {
    f ->
        f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector ||
        f.selector == sig:repay(Midnight.Obligation, uint256, address).selector ||
        f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector ||
        f.selector == sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
} {
    uint128 before = lastContinuousFeeAccrual(id, user);

    // block.timestamp must fit in uint128 (no truncation) and time must not go backwards.
    require e.block.timestamp < 2 ^ 128;
    require e.block.timestamp >= require_uint256(before);

    f(e, args);

    assert lastContinuousFeeAccrual(id, user) >= before;
}

rule feeConservation(env e, bytes32 id, address user, Midnight.Obligation obligation) {
    uint256 debtBefore = debtOf(id, user);
    uint128 pendingFeeBefore = pendingFee(id, user);

    repay(e, obligation, 0, user); // 0-amount repay only triggers accrual

    uint256 debtAfter = debtOf(id, user);
    uint128 pendingFeeAfter = pendingFee(id, user);

    // What left pendingFee was added to debt.
    assert to_mathint(debtAfter) - to_mathint(debtBefore) == to_mathint(pendingFeeBefore) - to_mathint(pendingFeeAfter);
}

rule pendingFeeOnlyIncreasesViaTake(env e, method f, calldataarg args, bytes32 id, address user) filtered {
    f ->
        f.selector == sig:repay(Midnight.Obligation, uint256, address).selector ||
        f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector ||
        f.selector == sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
} {
    uint128 pendingFeeBefore = pendingFee(id, user);

    f(e, args);

    assert pendingFee(id, user) <= pendingFeeBefore;
}

/// INVARIANTS ///

strong invariant notBorrowerAndLender(bytes32 id, address user)
    !isPassiveFeeRecipient(user) => sharesOf(id, user) == 0 || debtOf(id, user) == 0
    {
        preserved {
            requireInvariant noRemainingContinuousFeeWithoutDebt(id, user);
        }
    }

strong invariant noRemainingContinuousFeeWithoutDebt(bytes32 id, address user)
    debtOf(id, user) == 0 => pendingFee(id, user) == 0;

strong invariant debtImpliesLastAccrual(bytes32 id, address user)
    debtOf(id, user) > 0 => lastContinuousFeeAccrual(id, user) > 0
    {
        preserved with (env e) {
            require e.block.timestamp > 0;
            require e.block.timestamp < 2 ^ 128;
        }
    }

strong invariant pendingFeeImpliesLastAccrual(bytes32 id, address user)
    pendingFee(id, user) > 0 => lastContinuousFeeAccrual(id, user) > 0
    {
        preserved with (env e) {
            require e.block.timestamp > 0;
            require e.block.timestamp < 2 ^ 128;
        }
    }

strong invariant lenderHasNoPendingFee(bytes32 id, address user)
    !isPassiveFeeRecipient(user) && sharesOf(id, user) > 0 => pendingFee(id, user) == 0
    {
        preserved {
            requireInvariant notBorrowerAndLender(id, user);
            requireInvariant noRemainingContinuousFeeWithoutDebt(id, user);
        }
    }

strong invariant postMaturityNoPendingFee(bytes32 id, address user)
    ghostMaturity[id] > 0 && lastContinuousFeeAccrual(id, user) >= ghostMaturity[id] => pendingFee(id, user) == 0
    {
        preserved with (env e) {
            require e.block.timestamp > 0;
            require e.block.timestamp < 2 ^ 128;
            requireInvariant pendingFeeImpliesLastAccrual(id, user);
        }
    }

strong invariant totalUnitsEqualsSumDebtPlusWithdrawable(bytes32 id)
    totalUnits(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumSharesOf(bytes32 id)
    totalShares(id) == sumSharesOf[id];
