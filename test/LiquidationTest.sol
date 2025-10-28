// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MAX_LIF, WAD, ORACLE_PRICE_SCALE, AUCTION_DURATION} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

import "forge-std/console.sol";

contract LiquidationTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    Seizure[] internal recordedSeizures;
    address internal recordedBorrower;
    address internal recordedLiquidator;
    bytes internal recordedData;

    Seizure[] internal seizures;

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);
    }

    function testLiquidateHealthyPreMaturity(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);

        vm.expectRevert("position is not liquidatable");
        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateUnhealthyPreMaturity(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateHealthyPostMaturity(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        obligation.maturity = block.timestamp - 1;

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateUnhealthyPostMaturity(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        obligation.maturity = block.timestamp - 1;
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateNoOp(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateInconsistentInput(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        oracle.setPrice(0);
        seizures.push(Seizure({collateralIndex: 0, repaid: 1, seized: 1}));

        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateObligationUnitsInput(uint256 obligations, uint256 repaid) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligations);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), repaid);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.debtOf(borrower, id), obligations - repaid);
        assertEq(
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            initialCollateral - repaid.mulDivDown(ORACLE_PRICE_SCALE, 1e36 - 1).mulDivDown(MAX_LIF, WAD)
        );
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testLiquidateCollateralInput(uint256 obligations, uint256 seized) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);
        seized = bound(seized, 0, obligations.mulDivDown(MAX_LIF, WAD));
        oracle.setPrice(1e36 - 1);
        uint256 repaid = seized.mulDivUp(WAD, MAX_LIF).mulDivUp(1e36 - 1, ORACLE_PRICE_SCALE);
        deal(address(loanToken), address(this), repaid);
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: seized}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(loanToken.balanceOf(address(this)), 0, "loan token balance");
        assertApproxEqAbs(morphoV2.debtOf(borrower, id), obligations - repaid, 1, "debt"); // TODO fix approx
        assertEq(
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            initialCollateral - seized,
            "collateral"
        );
    }

    function testLiquidateCallback(uint256 obligations, uint256 repaid, bytes memory data) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligations);
        vm.assume(data.length > 0);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), obligations);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, data);

        assertEq(recordedSeizures.length, 1, "seizures length");
        assertEq(recordedSeizures[0].repaid, repaid, "repaid obligations");
        assertEq(recordedSeizures[0].seized, repaid.mulDivDown(ORACLE_PRICE_SCALE, 1e36 - 1).mulDivDown(MAX_LIF, WAD), "seized assets");
        assertEq(recordedBorrower, borrower, "borrower");
        assertEq(recordedLiquidator, address(this), "liquidator");
        assertEq(recordedData, data, "data");
    }

    // Test bad debt.

    function testRealizeOnlyBadDebt(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        oracle.setPrice(0.5e36); // TODO fuzz

        morphoV2.liquidate(obligation, seizures, borrower, ""); // empty seizures.

        // TODO assert bad debt.
    }

    function testLiquidateSeizedBadDebt(uint256 obligations, uint256 seized) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);
        seized = bound(seized, 0, initialCollateral);
        oracle.setPrice(0.5e36);
        deal(address(loanToken), address(this), obligations); // over-approx.
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: seized}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        // TODO assert bad debt
    }

    function testLiquidateRepaidBadDebt(uint256 obligations, uint256 repaid) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        oracle.setPrice(0.5e36);
        uint256 repayableDebt = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token).mulDivUp(WAD, MAX_LIF).mulDivUp(0.5e36, ORACLE_PRICE_SCALE);
        repaid = bound(repaid, 0, repayableDebt - 1); // TODO fix -1.
        deal(address(loanToken), address(this), repaid);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));
        
        morphoV2.liquidate(obligation, seizures, borrower, "");

        // TODO assert bad debt.
    }

    // Check that if there is bad debt it is possible to seize all assets.
    function testSeizeAllWhenBadDebt(uint256 obligations) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        Oracle oracle2 = new Oracle();
        obligation.collaterals[1].oracle = address(oracle2);
        id = toId(obligation);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);
        oracle.setPrice(ORACLE_PRICE_SCALE / 2); // TODO fuzz
        deal(address(loanToken), address(this), obligations); // not needed.
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: initialCollateral}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 0);
    }

    // post maturity liquidation.

    function testLiquidatePostMaturityFullLIF(uint256 obligations, uint256 repaid, uint256 delay) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligations);
        delay = bound(delay, 0, 100 weeks);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        vm.warp(obligation.maturity + AUCTION_DURATION + delay);
        deal(address(loanToken), address(this), obligations);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.debtOf(borrower, id), obligations - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            initialCollateral - repaid.mulDivDown(MAX_LIF, WAD),
            "collateral"
        );
    }

    function testLiquidatePostMaturityPartialLIF(uint256 obligations, uint256 repaid, uint256 delay) public {
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligations);
        delay = bound(delay, 1, AUCTION_DURATION);
        collateralize(obligation, borrower, obligations);
        setupObligation(obligation, obligations);
        vm.warp(obligation.maturity + delay);
        deal(address(loanToken), address(this), obligations);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        uint256 lif = WAD + (MAX_LIF - WAD) * delay / AUCTION_DURATION;

        assertEq(morphoV2.debtOf(borrower, id), obligations - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            initialCollateral - repaid.mulDivDown(lif, WAD),
            "collateral"
        );
    }

    // helpers.

    function onLiquidate(Seizure[] memory _seizures, address borrower, address liquidator, bytes memory data) public {
        for (uint256 i = 0; i < _seizures.length; i++) {
            recordedSeizures.push(_seizures[i]);
        }
        recordedBorrower = borrower;
        recordedLiquidator = liquidator;
        recordedData = data;
    }
}
