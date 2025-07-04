// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    Term internal term;
    bytes32 internal id;
    Collateral[] internal collaterals;
    Offer internal lendOffer;
    Offer internal borrowOffer;

    function setUp() public override {
        super.setUp();

        deal(address(loanToken), address(this), 100);
        deal(address(loanToken), address(lender), 100);
        deal(address(collateralToken1), address(this), 135);
        deal(address(collateralToken1), address(this), type(uint256).max);

        collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});

        term = Term(address(loanToken), collaterals, block.timestamp + 100);
        id = keccak256(abi.encode(term));

        lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            rate: 0.01e18 / 100,
            nonce: 0
        });

        borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            rate: 0.01e18 / 100,
            nonce: 0
        });

        terms.supplyCollateral(term, address(collateralToken1), 135, borrower);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        Term memory _term = Term(address(loanToken), collaterals, maturity);
        Offer memory offer;
        Signature memory sig;
        vm.expectRevert("maturity");
        terms.take(_term, 100, lender, offer, sig);
    }

    function testLend() public {
        terms.take(term, 100, lender, borrowOffer, sig(borrowOffer, borrowerSK));

        assertEq(terms.bondSharesOf(lender, id), 101, "lender bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "borrower debt");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(terms.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testBorrow() public {
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));

        assertEq(terms.bondSharesOf(lender, id), 101, "bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "lender debt");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(terms.consumed(lender, 0), 100, "lender nonce");
    }

    function testMatch() public {
        terms.take(term, 100, address(this), borrowOffer, sig(borrowOffer, borrowerSK));
        terms.take(term, 100, address(this), lendOffer, sig(lendOffer, lenderSK));

        assertEq(terms.bondSharesOf(address(this), id), 0, "bond shares");
        assertEq(terms.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 100, "balance");
        assertEq(terms.consumed(lender, 0), 100, "lender nonce");
        assertEq(terms.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testConsumed() public {
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));

        vm.expectRevert("consumed");
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));
    }

    function testTakePartialFill() public {
        terms.take(term, 50, borrower, lendOffer, sig(lendOffer, lenderSK));

        assertEq(terms.consumed(lender, 0), 50);

        vm.expectRevert("consumed");
        terms.take(term, 51, borrower, lendOffer, sig(lendOffer, lenderSK));

        terms.take(term, 50, borrower, lendOffer, sig(lendOffer, lenderSK));

        assertEq(terms.consumed(lender, 0), 100);
    }

    function testTakeOCO() public {
        Offer memory lendOffer2 = lendOffer;
        lendOffer2.maturity = block.timestamp + 200;
        Term memory term2 = term;
        term2.maturity = block.timestamp + 200;

        terms.take(term, 70, borrower, lendOffer, sig(lendOffer, lenderSK));

        vm.expectRevert("consumed");
        terms.take(term2, 31, borrower, lendOffer2, sig(lendOffer2, lenderSK));

        terms.supplyCollateral(term2, address(collateralToken1), 134, borrower);

        terms.take(term2, 30, borrower, lendOffer2, sig(lendOffer2, lenderSK));
        assertEq(terms.consumed(lender, 0), 100);
    }

    function testTakeMaturityPassed() public {
        vm.warp(block.timestamp + 101);
        vm.expectRevert("maturity");
        terms.take(term, 100, lender, lendOffer, sig(lendOffer, lenderSK));
    }

    function testTakeLendOfferCollateralMissing() public {
        lendOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));
    }

    function testTakeLendOfferLLTVMismatch() public {
        lendOffer.collaterals[0].lltv = 0.5e18;

        vm.expectRevert("LLTVs do not match");
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));
    }

    function testTakeLendOfferOraclesMismatch() public {
        lendOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));
    }

    function testTakeBorrowOfferTooMuchCollaterals() public {
        borrowOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, 100, lender, borrowOffer, sig(borrowOffer, borrowerSK));
    }

    function testTakeBorrowOfferLLTVMismatch() public {
        borrowOffer.collaterals[0].lltv = 0.99e18;

        vm.expectRevert("LLTVs do not match");
        terms.take(term, 100, lender, borrowOffer, sig(borrowOffer, borrowerSK));
    }

    function testTakeBorrowOfferOraclesMismatch() public {
        borrowOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        terms.take(term, 100, lender, borrowOffer, sig(borrowOffer, borrowerSK));
    }

    function testTakeSellerMakerNotHealthyMaker() public {
        terms.withdrawCollateral(term, address(collateralToken1), 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        terms.take(term, 100, lender, borrowOffer, sig(borrowOffer, borrowerSK));
    }

    function testTakeSellerTakerNotHealthy() public {
        terms.withdrawCollateral(term, address(collateralToken1), 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        terms.take(term, 100, borrower, lendOffer, sig(lendOffer, lenderSK));
    }
}
