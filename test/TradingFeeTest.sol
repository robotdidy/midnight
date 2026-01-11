// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = keccak256(abi.encode(obligation));

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 10000);

        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    // Normal trading fee. Proportional to amount traded.

    // Buy: the proportional trading fee is the limiting one:
    // iff tradingFee <= interestCutLimit * (1 - P_S)/P_S
    // iff P_S <= interestCutLimit / (tradingFee + interestCutLimit)

    // Sell: the proportional trading fee is the limiting one:
    // iff (P_B - interestCutLimit) / (1 - interestCutLimit) <= P_B / (1 + tradingFee)
    // iff P_B <= interestCutLimit * (1 + tradingFee) / (tradingFee + interestCutLimit)

    function testBuyBuyerAssetsProportional(uint256 buyerAssets, uint256 sellerPrice, uint256 tradingFee) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellBuyerAssetsProportional(uint256 tradingFee, uint256 buyerPrice, uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, buyerPrice);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(
            loanToken.balanceOf(feeRecipient), expectedFee, buyerAssets / 1e6 + 100, "fee recipient balance"
        );
    }

    function testBuySellerAssetsProportional(uint256 tradingFee, uint256 sellerPrice, uint256 sellerAssets) public {
        sellerAssets = bound(sellerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, sellerAssets, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellSellerAssetsProportional(uint256 tradingFee, uint256 buyerPrice, uint256 sellerAssets) public {
        sellerAssets = bound(sellerAssets, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 0.05 ether);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 10);
        take(0, sellerAssets, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyObligationUnitsProportional(uint256 tradingFee, uint256 sellerPrice, uint256 obligationUnits)
        public
    {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.01 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 10);
        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationUnitsProportional(uint256 tradingFee, uint256 buyerPrice, uint256 obligationUnits)
        public
    {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 0.05 ether);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyObligationSharesProportional(uint256 tradingFee, uint256 sellerPrice, uint256 obligationShares)
        public
    {
        obligationShares = bound(obligationShares, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = obligationShares.mulDivDown(sellerPrice, WAD);
        uint256 expectedBuyerAssets = obligationShares.mulDivDown(buyerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationSharesProportional(uint256 tradingFee, uint256 buyerPrice, uint256 obligationShares)
        public
    {
        obligationShares = bound(obligationShares, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 0.05 ether);
        morphoV2.setTradingFee(id, tradingFee, 0, 0, 0, 0);
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationShares.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationShares.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }
}
