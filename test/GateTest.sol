// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {IEnterGate, ILiquidatorGate} from "../src/interfaces/IGate.sol";
import {LIQUIDATION_CURSOR_LOW, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract WhitelistGate is IEnterGate, ILiquidatorGate {
    mapping(address => bool) public whitelisted;

    function setWhitelisted(address account, bool status) external {
        whitelisted[account] = status;
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return whitelisted[account];
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return whitelisted[account];
    }

    function canLiquidate(address account) external view returns (bool) {
        return whitelisted[account];
    }
}

contract GateTest is BaseTest {
    WhitelistGate internal gate;
    Obligation internal obligation;
    Obligation internal gatedObligation;
    bytes32 internal gatedId;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        gate = new WhitelistGate();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    oracle: address(oracle1),
                    maxLif: maxLif(0.75e18, LIQUIDATION_CURSOR_LOW)
                })
            );
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        gatedObligation.loanToken = address(loanToken);
        gatedObligation.maturity = block.timestamp + 100;
        gatedObligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    oracle: address(oracle1),
                    maxLif: maxLif(0.75e18, LIQUIDATION_CURSOR_LOW)
                })
            );
        gatedObligation.collaterals = sortCollaterals(gatedObligation.collaterals);
        gatedObligation.enterGate = address(gate);
        gatedObligation.liquidatorGate = address(gate);

        gatedId = toId(gatedObligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligationUnits = type(uint256).max;
        lenderOffer.obligation = gatedObligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationUnits = type(uint256).max;
        borrowerOffer.obligation = gatedObligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;

        deal(address(loanToken), lender, type(uint256).max);
    }

    // --- Enter gate tests ---

    function testEnterGateBlocksNonWhitelistedBuyer(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        gate.setWhitelisted(borrower, true);

        vm.expectRevert("buyer gated from increasing credit");
        take(obligationUnits, lender, borrowerOffer);
    }

    function testEnterGateBlocksNonWhitelistedSeller(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        gate.setWhitelisted(lender, true);

        vm.expectRevert("seller gated from increasing debt");
        take(obligationUnits, borrower, lenderOffer);
    }

    function testEnterGateAllowsWhitelistedUsers(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        take(obligationUnits, lender, borrowerOffer);

        assertGt(midnight.creditOf(gatedId, lender), 0, "lender should have credit");
        assertGt(midnight.debtOf(gatedId, borrower), 0, "borrower should have debt");
    }

    // --- No gate check on exit  ---

    function testNoEnterGateCheckWhenBorrowerIsExitingBorrower(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(otherBorrower, true);

        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        Offer memory otherBorrowerOffer;
        otherBorrowerOffer.buy = false;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.receiverIfMakerIsSeller = otherBorrower;
        otherBorrowerOffer.obligationUnits = type(uint256).max;
        otherBorrowerOffer.obligation = gatedObligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = MAX_TICK;

        collateralize(gatedObligation, otherBorrower, obligationUnits);

        gate.setWhitelisted(borrower, false);

        take(obligationUnits, borrower, otherBorrowerOffer);

        assertEq(midnight.debtOf(gatedId, borrower), 0, "borrower should have exited debt");
    }

    function testNoGateCheckWhenBothExit(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT / 2);

        gate.setWhitelisted(otherLender, true);
        gate.setWhitelisted(otherBorrower, true);

        deal(address(loanToken), otherLender, obligationUnits);
        collateralize(gatedObligation, otherBorrower, obligationUnits);

        Offer memory otherLenderOffer;
        otherLenderOffer.buy = true;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.obligationUnits = type(uint256).max;
        otherLenderOffer.obligation = gatedObligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = MAX_TICK;

        take(obligationUnits, otherBorrower, otherLenderOffer);

        gate.setWhitelisted(otherLender, false);
        gate.setWhitelisted(otherBorrower, false);

        // Both parties exit
        Offer memory exitOffer;
        exitOffer.buy = false;
        exitOffer.maker = otherLender;
        exitOffer.receiverIfMakerIsSeller = otherLender;
        exitOffer.obligationUnits = type(uint256).max;
        exitOffer.obligation = gatedObligation;
        exitOffer.expiry = block.timestamp + 200;
        exitOffer.tick = MAX_TICK;

        deal(address(loanToken), otherBorrower, obligationUnits);
        take(obligationUnits, otherBorrower, exitOffer);

        assertEq(midnight.debtOf(gatedId, otherBorrower), 0, "otherBorrower should have exited");
    }

    function testNoGateCheckOnRepay(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        gate.setWhitelisted(borrower, false);

        deal(address(loanToken), borrower, obligationUnits);
        vm.prank(borrower);
        midnight.repay(gatedObligation, obligationUnits, borrower);

        assertEq(midnight.debtOf(gatedId, borrower), 0, "borrower should have repaid");
    }

    function testNoGateCheckOnWithdraw(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        deal(address(loanToken), borrower, obligationUnits);
        vm.prank(borrower);
        midnight.repay(gatedObligation, obligationUnits, borrower);

        gate.setWhitelisted(lender, false);

        vm.prank(lender);
        midnight.withdraw(gatedObligation, obligationUnits, lender, lender);

        assertEq(midnight.creditOf(gatedId, lender), 0, "lender should have withdrawn");
    }

    // --- Liquidator gate tests ---

    function testLiquidatorGateOnLiquidation(uint256 obligationUnits, bool isWhitelisted) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(liquidator, isWhitelisted);

        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        Oracle(gatedObligation.collaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 2);

        deal(address(loanToken), liquidator, obligationUnits);
        vm.prank(liquidator);
        if (!isWhitelisted) vm.expectRevert("liquidator gated from liquidating");
        midnight.liquidate(gatedObligation, 0, 1, 0, borrower, "");
    }

    function testLiquidatorGateOnBadDebt(uint256 obligationUnits, bool isWhitelisted) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(liquidator, isWhitelisted);

        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        Oracle(gatedObligation.collaterals[0].oracle).setPrice(0);

        vm.prank(liquidator);
        if (!isWhitelisted) vm.expectRevert("liquidator gated from liquidating");
        midnight.liquidate(gatedObligation, 0, 0, 0, borrower, "");
    }

    // --- Default (no gate) tests ---

    function testNoGateMeansUnrestricted(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(obligation, borrower, obligationUnits);

        Offer memory ungatedLenderOffer;
        ungatedLenderOffer.buy = true;
        ungatedLenderOffer.maker = lender;
        ungatedLenderOffer.obligationUnits = type(uint256).max;
        ungatedLenderOffer.obligation = obligation;
        ungatedLenderOffer.expiry = block.timestamp + 200;
        ungatedLenderOffer.tick = MAX_TICK;

        take(obligationUnits, borrower, ungatedLenderOffer);

        bytes32 ungatedId = toId(obligation);
        assertGt(midnight.debtOf(ungatedId, borrower), 0);
    }

    // --- Obligation identity tests ---

    function testDifferentGatesProduceDifferentIds() public view {
        bytes32 ungatedId = toId(obligation);
        assertNotEq(ungatedId, gatedId, "gated and ungated obligations should have different IDs");
    }
}
