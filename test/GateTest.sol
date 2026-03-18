// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {ITakerGate, ILiquidatorGate} from "../src/interfaces/IGate.sol";
import {LIQUIDATION_CURSOR_LOW} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract WhitelistGate is ITakerGate, ILiquidatorGate {
    mapping(address => bool) public whitelisted;

    function setWhitelisted(address account, bool status) external {
        whitelisted[account] = status;
    }

    function canLend(address account) external view returns (bool) {
        return whitelisted[account];
    }

    function canBorrow(address account) external view returns (bool) {
        return whitelisted[account];
    }

    function canLiquidate(address account) external view returns (bool) {
        return whitelisted[account];
    }
}

contract GateTest is BaseTest {
    using UtilsLib for uint256;

    WhitelistGate internal gate;
    Obligation internal obligation;
    Obligation internal gatedObligation;
    bytes32 internal gatedId;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        gate = new WhitelistGate();

        // Ungated obligation (for reference / path testing).
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

        // Gated obligation (same terms, but with gates).
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
        gatedObligation.takerGate = address(gate);
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

    // --- Lender gate tests ---

    function testLenderGateBlocksNonWhitelistedLender(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        // Borrower is whitelisted, lender is not.
        gate.setWhitelisted(borrower, true);

        vm.expectRevert("buyer gated from lending");
        take(obligationUnits, lender, borrowerOffer);
    }

    function testLenderGateAllowsWhitelistedLender(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        take(obligationUnits, lender, borrowerOffer);

        assertGt(midnight.creditOf(gatedId, lender), 0, "lender should have credit");
    }

    // --- Borrower gate tests ---

    function testBorrowerGateBlocksNonWhitelistedBorrower(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        // Lender is whitelisted, borrower is not.
        gate.setWhitelisted(lender, true);

        vm.expectRevert("seller gated from borrowing");
        take(obligationUnits, borrower, lenderOffer);
    }

    function testBorrowerGateAllowsWhitelistedBorrower(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedObligation, borrower, obligationUnits);

        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        take(obligationUnits, borrower, lenderOffer);

        assertGt(midnight.debtOf(gatedId, borrower), 0, "borrower should have debt");
    }

    // --- No gate check on exit paths ---

    function testNoLenderGateCheckWhenBorrowerIsExitingBorrower(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(otherBorrower, true);

        // Setup: lender lends, borrower borrows.
        deal(address(loanToken), lender, obligationUnits);
        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        // Now borrower (who has debt) takes borrowerOffer as buyer to exit debt.
        // Buyer is exiting borrower + seller enters as borrower.
        // Even though lender gate is set, buyer (borrower) is not checked because they're exiting.
        Offer memory otherBorrowerOffer;
        otherBorrowerOffer.buy = false;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.receiverIfMakerIsSeller = otherBorrower;
        otherBorrowerOffer.obligationUnits = type(uint256).max;
        otherBorrowerOffer.obligation = gatedObligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = MAX_TICK;

        collateralize(gatedObligation, otherBorrower, obligationUnits);

        // Remove lender whitelist.
        gate.setWhitelisted(lender, false);

        // borrower takes this offer as buyer (exiting debt), otherBorrower enters as seller (new borrower).
        take(obligationUnits, borrower, otherBorrowerOffer);

        assertEq(midnight.debtOf(gatedId, borrower), 0, "borrower should have exited debt");
    }

    function testNoGateCheckWhenBothExit(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT / 2);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        // Setup: lender lends, borrower borrows.
        deal(address(loanToken), lender, obligationUnits);
        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        // Borrower repays to make funds withdrawable.
        deal(address(loanToken), borrower, obligationUnits);
        vm.prank(borrower);
        midnight.repay(gatedObligation, obligationUnits, borrower);

        // Remove all whitelisting. Path 4 (both exit) should not check gates.
        gate.setWhitelisted(lender, false);
        gate.setWhitelisted(borrower, false);

        // Lender exits by selling shares. Offer from lender (seller = lender exiting).
        // Borrower (buyer) exits debt — but borrower has no debt now, so buyer is a new lender.
        // Actually for path 4, we need buyer with debt and seller with shares.
        // Let's create a new scenario for path 4.

        // Re-setup with otherLender and otherBorrower.
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

        // Now otherBorrower has debt, otherLender has shares. Path 4: both exit.
        // otherBorrower (buyer, has debt) buys from otherLender (seller, has shares).
        Offer memory exitOffer;
        exitOffer.buy = false;
        exitOffer.maker = otherLender;
        exitOffer.receiverIfMakerIsSeller = otherLender;
        exitOffer.obligationUnits = type(uint256).max;
        exitOffer.obligation = gatedObligation;
        exitOffer.expiry = block.timestamp + 200;
        exitOffer.tick = MAX_TICK;

        // Both parties need to remain whitelisted since gates are always checked.
        deal(address(loanToken), otherBorrower, obligationUnits);
        take(obligationUnits, otherBorrower, exitOffer);

        assertEq(midnight.debtOf(gatedId, otherBorrower), 0, "otherBorrower should have exited");
    }

    // --- Liquidator gate tests ---

    function testLiquidatorGateBlocksNonWhitelistedLiquidator(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        deal(address(loanToken), lender, obligationUnits);
        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        // Make position liquidatable by dropping oracle price.
        Oracle(gatedObligation.collaterals[0].oracle).setPrice(0);

        // Liquidator is NOT whitelisted.
        deal(address(loanToken), liquidator, obligationUnits);
        vm.prank(liquidator);
        vm.expectRevert("liquidator gated from liquidating");
        midnight.liquidate(gatedObligation, 0, 0, 0, borrower, "");
    }

    function testLiquidatorGateAllowsWhitelistedLiquidator(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(liquidator, true);

        deal(address(loanToken), lender, obligationUnits);
        collateralize(gatedObligation, borrower, obligationUnits);
        take(obligationUnits, lender, borrowerOffer);

        // Make position liquidatable.
        Oracle(gatedObligation.collaterals[0].oracle).setPrice(0);

        deal(address(loanToken), liquidator, obligationUnits);
        vm.prank(liquidator);
        midnight.liquidate(gatedObligation, 0, 0, 0, borrower, "");
    }

    // --- Default (no gate) tests ---

    function testNoGateMeansUnrestricted(uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT * 3 / 4);
        deal(address(loanToken), lender, obligationUnits);
        collateralize(obligation, borrower, obligationUnits);

        Offer memory ungatedLenderOffer;
        ungatedLenderOffer.buy = true;
        ungatedLenderOffer.maker = lender;
        ungatedLenderOffer.obligationUnits = type(uint256).max;
        ungatedLenderOffer.obligation = obligation;
        ungatedLenderOffer.expiry = block.timestamp + 200;
        ungatedLenderOffer.tick = MAX_TICK;

        // No gates set — anyone can participate.
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
