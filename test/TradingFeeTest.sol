// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using MathLib for uint256;

    Term internal term;
    bytes32 internal id;
    Offer internal lendOffer;
    Offer internal borrowOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        deal(address(loanToken), address(this), 1000 ether);
        deal(address(loanToken), address(lender), 1000 ether);
        deal(address(loanToken), address(borrower), 1000 ether);
        deal(address(collateralToken1), address(this), type(uint256).max);

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});
        collaterals = sortCollaterals(collaterals);

        term.loanToken = address(loanToken);
        term.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            term.collaterals.push(collaterals[i]);
        }

        id = keccak256(abi.encode(term));

        lendOffer.buy = true;
        lendOffer.offering = lender;
        lendOffer.assets = 100 ether;
        lendOffer.loanToken = address(loanToken);
        lendOffer.maturity = block.timestamp + 100;
        lendOffer.start = block.timestamp;
        lendOffer.expiry = block.timestamp + 200;
        lendOffer.startPrice = 1 ether;
        lendOffer.expiryPrice = 1 ether;
        lendOffer.nonce = 0;

        for (uint256 i = 0; i < collaterals.length; i++) {
            lendOffer.collaterals.push(collaterals[i]);
        }

        borrowOffer.buy = false;
        borrowOffer.offering = borrower;
        borrowOffer.assets = 100 ether;
        borrowOffer.loanToken = address(loanToken);
        borrowOffer.maturity = block.timestamp + 100;
        borrowOffer.expiry = block.timestamp + 200;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;
        borrowOffer.nonce = 0;

        for (uint256 i = 0; i < collaterals.length; i++) {
            borrowOffer.collaterals.push(collaterals[i]);
        }

        terms.supplyCollateral(term, address(collateralToken1), 200 ether, borrower);

        // Set up trading fee for tests
        terms.setTradingFee(address(loanToken), 0.05e18); // 5%
        terms.setTradingFeeRecipient(address(loanToken), feeRecipient);
    }

    function testTradingFeeSetup() public view {
        assertEq(terms.tradingFeePct(address(loanToken)), 0.05e18, "trading fee percentage");
        assertEq(terms.tradingFeeRecipient(address(loanToken)), feeRecipient, "fee recipient");
    }

    function testBuyerAssetsWithFee() public {
        uint256 buyerAssets = 100 ether;
        uint256 price = 0.9 ether;
        uint256 feePct = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        // other formula to arrive to the same result.
        uint256 expectedBonds = buyerAssets * 1e18 / price;
        uint256 expectedFee = (expectedBonds - buyerAssets).mulDivDown(feePct, 1e18);
        uint256 expectedSellerAssets = buyerAssets - expectedFee;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, buyerAssets, 0, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(terms.bondSharesOf(lender, id), expectedBonds, "bonds");
        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, "fee recipient balance");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - buyerAssets, "lender balance");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + expectedSellerAssets, "borrower balance");
    }

    function testSellerAssetsWithFee() public {
        uint256 sellerAssets = 90 ether;
        uint256 price = 0.9 ether;
        uint256 feePct = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(1e18, 1e18 + feePct - feePct.mulDivDown(1e18, price));
        uint256 expectedBonds = expectedBuyerAssets.mulDivDown(1e18, price);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, 0, sellerAssets, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, "fee recipient balance");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + sellerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - expectedBuyerAssets, "lender balance");
    }

    function testBondsWithFee() public {
        uint256 bonds = 100 ether;
        uint256 price = 0.9 ether;
        uint256 feePct = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedBuyerAssets = bonds * price / 1e18;
        uint256 expectedFee = (bonds - expectedBuyerAssets).mulDivDown(feePct, 1e18);
        uint256 expectedSellerAssets = expectedBuyerAssets - expectedFee;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, 0, 0, bonds, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, "fee recipient balance");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + expectedSellerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - expectedBuyerAssets, "lender balance");
    }

    function testZeroTradingFee() public {
        terms.setTradingFee(address(loanToken), 0);
        uint256 buyerAssets = 100 ether;
        borrowOffer.startPrice = 0.9 ether;
        borrowOffer.expiryPrice = 0.9 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, buyerAssets, 0, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + buyerAssets, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - buyerAssets, "lender pays full amount");
    }

    function testBuyerAssetsNoInterest() public {
        uint256 buyerAssets = 100 ether;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, buyerAssets, 0, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + buyerAssets, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - buyerAssets, "lender pays full amount");
    }

    function testSellerAssetsNoInterest() public {
        uint256 sellerAssets = 100 ether;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, 0, sellerAssets, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + sellerAssets, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - sellerAssets, "lender pays full amount");
    }

    function testBondsNoInterest() public {
        uint256 bonds = 100 ether;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        terms.take(term, 0, 0, bonds, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + bonds, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - bonds, "lender pays full amount");
    }
}
