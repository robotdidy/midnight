// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {ILenderGate, IBorrowerGate, ILiquidatorGate} from "../src/interfaces/IGate.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {ERC20} from "./helpers/ERC20.sol";

contract WhitelistGate is ILenderGate, IBorrowerGate, ILiquidatorGate {
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
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        // Gated obligation (same terms, but with gates).
        gatedObligation.loanToken = address(loanToken);
        gatedObligation.maturity = block.timestamp + 100;
        gatedObligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        gatedObligation.collaterals = sortCollaterals(gatedObligation.collaterals);
        gatedObligation.lenderGate = address(gate);
        gatedObligation.borrowerGate = address(gate);
        gatedObligation.liquidatorGate = address(gate);

        gatedId = toId(gatedObligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.obligation = gatedObligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.obligation = gatedObligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        deal(address(loanToken), lender, type(uint256).max);
    }

    // --- Lender gate tests ---

    function testLenderGateBlocksNonWhitelistedLender(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        collateralize(gatedObligation, borrower, buyerAssets);

        // Borrower is whitelisted, lender is not.
        gate.setWhitelisted(borrower, true);

        vm.expectRevert("lender gated from lending");
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);
    }

    function testLenderGateAllowsWhitelistedLender(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        collateralize(gatedObligation, borrower, buyerAssets);

        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertGt(morphoV2.sharesOf(gatedId, lender), 0, "lender should have shares");
    }

    // --- Borrower gate tests ---

    function testBorrowerGateBlocksNonWhitelistedBorrower(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        collateralize(gatedObligation, borrower, buyerAssets);

        // Lender is whitelisted, borrower is not.
        gate.setWhitelisted(lender, true);

        vm.expectRevert("borrower gated from borrowing");
        take(0, 0, buyerAssets, 0, borrower, lenderOffer);
    }

    function testBorrowerGateAllowsWhitelistedBorrower(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        collateralize(gatedObligation, borrower, buyerAssets);

        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        take(0, 0, buyerAssets, 0, borrower, lenderOffer);

        assertGt(morphoV2.debtOf(gatedId, borrower), 0, "borrower should have debt");
    }

    // --- No gate check on exit paths ---

    function testNoLenderGateCheckWhenBorrowerIsExitingBorrower(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(otherBorrower, true);

        // Setup: lender lends, borrower borrows.
        deal(address(loanToken), lender, buyerAssets);
        collateralize(gatedObligation, borrower, buyerAssets);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        // Now borrower (who has debt) takes borrowerOffer as buyer to exit debt.
        // Buyer is exiting borrower + seller enters as borrower.
        // Even though lender gate is set, buyer (borrower) is not checked because they're exiting.
        Offer memory otherBorrowerOffer;
        otherBorrowerOffer.buy = false;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.receiverIfMakerIsSeller = otherBorrower;
        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.obligation = gatedObligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = TICK_RANGE;

        collateralize(gatedObligation, otherBorrower, buyerAssets);

        // Remove lender whitelist.
        gate.setWhitelisted(lender, false);

        // borrower takes this offer as buyer (exiting debt), otherBorrower enters as seller (new borrower).
        take(0, 0, buyerAssets, 0, borrower, otherBorrowerOffer);

        assertEq(morphoV2.debtOf(gatedId, borrower), 0, "borrower should have exited debt");
    }

    function testNoGateCheckWhenBothExit(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        // Setup: lender lends, borrower borrows.
        deal(address(loanToken), lender, buyerAssets);
        collateralize(gatedObligation, borrower, buyerAssets);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        // Borrower repays to make funds withdrawable.
        deal(address(loanToken), borrower, buyerAssets);
        vm.prank(borrower);
        morphoV2.repay(gatedObligation, buyerAssets, borrower);

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

        deal(address(loanToken), otherLender, buyerAssets);
        collateralize(gatedObligation, otherBorrower, buyerAssets);

        Offer memory otherLenderOffer;
        otherLenderOffer.buy = true;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.obligation = gatedObligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = TICK_RANGE;

        take(0, 0, buyerAssets, 0, otherBorrower, otherLenderOffer);

        // Now otherBorrower has debt, otherLender has shares. Path 4: both exit.
        // otherBorrower (buyer, has debt) buys from otherLender (seller, has shares).
        Offer memory exitOffer;
        exitOffer.buy = false;
        exitOffer.maker = otherLender;
        exitOffer.receiverIfMakerIsSeller = otherLender;
        exitOffer.assets = type(uint256).max;
        exitOffer.obligation = gatedObligation;
        exitOffer.expiry = block.timestamp + 200;
        exitOffer.tick = TICK_RANGE;

        // Remove all whitelisting.
        gate.setWhitelisted(otherLender, false);
        gate.setWhitelisted(otherBorrower, false);

        // Should succeed: neither gate is checked because both are exiting.
        deal(address(loanToken), otherBorrower, buyerAssets);
        take(0, 0, buyerAssets, 0, otherBorrower, exitOffer);

        assertEq(morphoV2.debtOf(gatedId, otherBorrower), 0, "otherBorrower should have exited");
        assertEq(morphoV2.sharesOf(gatedId, otherLender), 0, "otherLender should have exited");
    }

    // --- Liquidator gate tests ---

    function testLiquidatorGateBlocksNonWhitelistedLiquidator(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        deal(address(loanToken), lender, buyerAssets);
        collateralize(gatedObligation, borrower, buyerAssets);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        // Make position liquidatable by dropping oracle price.
        Oracle(gatedObligation.collaterals[0].oracle).setPrice(0);

        // Liquidator is NOT whitelisted.
        deal(address(loanToken), liquidator, buyerAssets);
        vm.prank(liquidator);
        vm.expectRevert("liquidator gated from liquidating");
        morphoV2.liquidate(gatedObligation, 0, 0, 0, borrower, "");
    }

    function testLiquidatorGateAllowsWhitelistedLiquidator(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(liquidator, true);

        deal(address(loanToken), lender, buyerAssets);
        collateralize(gatedObligation, borrower, buyerAssets);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        // Make position liquidatable.
        Oracle(gatedObligation.collaterals[0].oracle).setPrice(0);

        deal(address(loanToken), liquidator, buyerAssets);
        vm.prank(liquidator);
        morphoV2.liquidate(gatedObligation, 0, 0, 0, borrower, "");
    }

    // --- Default (no gate) tests ---

    function testNoGateMeansUnrestricted(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 1, MAX_TEST_AMOUNT);
        deal(address(loanToken), lender, buyerAssets);
        collateralize(obligation, borrower, buyerAssets);

        Offer memory ungatedLenderOffer;
        ungatedLenderOffer.buy = true;
        ungatedLenderOffer.maker = lender;
        ungatedLenderOffer.assets = type(uint256).max;
        ungatedLenderOffer.obligation = obligation;
        ungatedLenderOffer.expiry = block.timestamp + 200;
        ungatedLenderOffer.tick = TICK_RANGE;

        // No gates set — anyone can participate.
        take(0, 0, buyerAssets, 0, borrower, ungatedLenderOffer);

        bytes32 ungatedId = toId(obligation);
        assertGt(morphoV2.sharesOf(ungatedId, lender), 0);
        assertGt(morphoV2.debtOf(ungatedId, borrower), 0);
    }

    // --- Obligation identity tests ---

    function testDifferentGatesProduceDifferentIds() public view {
        bytes32 ungatedId = toId(obligation);
        assertNotEq(ungatedId, gatedId, "gated and ungated obligations should have different IDs");
    }

    // --- View function tests ---

    function testCanLendViewFunction() public {
        gate.setWhitelisted(lender, true);

        assertTrue(morphoV2.canLend(gatedObligation, lender), "whitelisted should pass");
        assertFalse(morphoV2.canLend(gatedObligation, borrower), "non-whitelisted should fail");
        assertTrue(morphoV2.canLend(obligation, borrower), "no gate should always pass");
    }

    function testCanBorrowViewFunction() public {
        gate.setWhitelisted(borrower, true);

        assertTrue(morphoV2.canBorrow(gatedObligation, borrower), "whitelisted should pass");
        assertFalse(morphoV2.canBorrow(gatedObligation, lender), "non-whitelisted should fail");
        assertTrue(morphoV2.canBorrow(obligation, lender), "no gate should always pass");
    }

    function testCanLiquidateViewFunction() public {
        gate.setWhitelisted(liquidator, true);

        assertTrue(morphoV2.canLiquidate(gatedObligation, liquidator), "whitelisted should pass");
        assertFalse(morphoV2.canLiquidate(gatedObligation, lender), "non-whitelisted should fail");
        assertTrue(morphoV2.canLiquidate(obligation, lender), "no gate should always pass");
    }
}
