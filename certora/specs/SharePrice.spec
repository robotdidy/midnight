// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;

    function _.price() external => NONDET;

    // Summaries to avoid SMT solver timeout.
    function tradingFee(bytes20, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes20, address) internal returns (bool) => NONDET;

    // Callback summaries for take, liquidate, and flashLoan.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
}

// Check the ratio of units over shares is below or equal to 1.
strong invariant sharePriceBelowOrEqOne(bytes20 id)
    totalShares(id) >= totalUnits(id);

/// Liquidation without bad debt preserves virtual share price.
rule sharePriceDoesNotDecreaseByLiquidateNoBadDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes20 id
) {
    requireInvariant sharePriceBelowOrEqOne(id);

    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    // unitsAfter == unitsBefore <==> badDebt == 0 (no bad debt socialization occurred)
    assert unitsAfter == unitsBefore => (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);
}



/// Virtual share price = (totalUnits+1)/(totalShares+1) monotonicity.
rule sharePriceDoesNotDecrease(bytes20 id, method f) filtered {
    f -> f.selector != sig:multicall(bytes[]).selector
      && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector 
      && !f.isView
} {

    // We need it otherwise rounding down to 0 creates shares with no backing units
    // for withdraw +1 virtual liquidity makes exchange rate differ from actual pool ratio when totalShares > totalUnits
    requireInvariant sharePriceBelowOrEqOne(id);

    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    env e;
    calldataarg args;
    f(e, args);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    assert (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);
}