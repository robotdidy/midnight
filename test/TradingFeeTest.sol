// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lendOffer;
    Offer internal borrowOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

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

        id = keccak256(abi.encode(obligation));

        lendOffer.obligation = obligation;
        lendOffer.buy = true;
        lendOffer.maker = lender;
        lendOffer.assets = 100 ether;
        lendOffer.start = block.timestamp;
        lendOffer.expiry = block.timestamp + 200;
        lendOffer.startPrice = 1 ether;
        lendOffer.expiryPrice = 1 ether;

        borrowOffer.obligation = obligation;
        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = 100 ether;
        borrowOffer.expiry = block.timestamp + 200;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        deal(address(loanToken), address(this), 1000 ether);
        deal(address(loanToken), address(lender), 1000 ether);
        deal(address(loanToken), address(borrower), 1000 ether);
        deal(obligation.collaterals[0].token, address(this), type(uint256).max);

        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 200 ether, borrower);

        // Set up trading fee for tests
        morphoV2.setTradingFee(id, 0.05e18, 1e18); // 5%
        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    // Helpers

    function take(
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        Offer memory offer
    ) public {
        morphoV2.take(
            buyerAssets,
            sellerAssets,
            obligationUnits,
            obligationShares,
            (offer.maker == borrower ? lender : borrower),
            offer,
            sig(root([offer]), (offer.maker == borrower ? borrowerSecretKey : lenderSecretKey)),
            root([offer]),
            proof([offer]),
            address(0),
            hex""
        );
    }

    function testTradingFeeSetup() public view {
        (uint128 _slope, uint128 _max) = morphoV2.tradingFee(id);
        assertEq(_slope, 0.05e18, "slope");
        assertEq(_max, 1e18, "max");
        assertEq(morphoV2.tradingFeeRecipient(), feeRecipient, "fee recipient");
    }

    // Fee proportional to interest.

    function testBuyerAssetsLend() public {
        uint256 buyerAssets = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(1e18, 1e18 + fee.mulDivDown(1e18, price) - fee);
        uint256 expectedUnits = expectedSellerAssets.mulDivDown(1e18, price);
        uint256 expectedFee = (expectedUnits - expectedSellerAssets) * fee / 1e18;

        take(buyerAssets, 0, 0, 0, borrowOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyerAssetsBorrow() public {
        uint256 buyerAssets = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        lendOffer.startPrice = price;
        lendOffer.expiryPrice = price;

        uint256 expectedUnits = buyerAssets.mulDivDown(1e18, price);
        uint256 expectedSellerAssets = (buyerAssets - fee.mulDivDown(expectedUnits, 1e18)).mulDivDown(1e18, 1e18 - fee);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        take(buyerAssets, 0, 0, 0, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellerAssetsLend() public {
        uint256 sellerAssets = 90 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedUnits = sellerAssets.mulDivDown(1e18, price);
        uint256 expectedFee = (expectedUnits - sellerAssets) * fee / 1e18;

        take(0, sellerAssets, 0, 0, borrowOffer);

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient balance");
    }

    function testSellerAssetsBorrow() public {
        uint256 sellerAssets = 90 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        lendOffer.startPrice = price;
        lendOffer.expiryPrice = price;

        uint256 expectedBuyerAssets =
            (sellerAssets.mulDivDown(1e18 - fee, 1e18)).mulDivDown(1e18, 1e18 - fee.mulDivDown(1e18, price));
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        take(0, sellerAssets, 0, 0, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 200, "fee recipient balance");
    }

    function testObligationUnitsLend() public {
        uint256 obligationUnits = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedSellerAssets = obligationUnits * price / 1e18;
        uint256 expectedFee = (obligationUnits - expectedSellerAssets) * fee / 1e18;

        take(0, 0, obligationUnits, 0, borrowOffer);

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient balance");
    }

    function testObligationUnitsBorrow() public {
        uint256 obligationUnits = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        lendOffer.startPrice = price;
        lendOffer.expiryPrice = price;

        uint256 expectedBuyerAssets = obligationUnits * price / 1e18;
        uint256 expectedSellerAssets =
            (expectedBuyerAssets - fee.mulDivDown(obligationUnits, 1e18)).mulDivDown(1e18, 1e18 - fee);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        take(0, 0, obligationUnits, 0, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    // Fee proportional to amount traded.

    function testBuyerAssetsLendMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 buyerAssets = 100 ether;
        borrowOffer.startPrice = 0.9 ether;
        borrowOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(1e18, 1e18 + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(buyerAssets, 0, 0, 0, borrowOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyerAssetsBorrowMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 buyerAssets = 100 ether;
        lendOffer.startPrice = 0.9 ether;
        lendOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(1e18, 1e18 + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(buyerAssets, 0, 0, 0, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellerAssetsLendMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 sellerAssets = 100 ether;
        borrowOffer.startPrice = 0.9 ether;
        borrowOffer.expiryPrice = 0.9 ether;

        uint256 expectedFee = sellerAssets / 1000;

        take(0, sellerAssets, 0, 0, borrowOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellerAssetsBorrowMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 sellerAssets = 90 ether;
        lendOffer.startPrice = 0.9 ether;
        lendOffer.expiryPrice = 0.9 ether;

        uint256 expectedFee = sellerAssets / 1000;

        take(0, sellerAssets, 0, 0, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testObligationUnitsLendMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 obligationUnits = 100 ether;
        borrowOffer.startPrice = 0.9 ether;
        borrowOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = obligationUnits * 0.9 ether / 1e18;
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, obligationUnits, 0, borrowOffer);

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient balance");
    }

    function testObligationUnitsBorrowMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 obligationUnits = 100 ether;
        lendOffer.startPrice = 0.9 ether;
        lendOffer.expiryPrice = 0.9 ether;

        uint256 expectedBuyerAssets = obligationUnits * 0.9 ether / 1e18;
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(1e18, 1e18 + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, obligationUnits, 0, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testObligationSharesLendMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 obligationShares = 100 ether;
        borrowOffer.startPrice = 0.9 ether;
        borrowOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = obligationShares * 0.9 ether / 1e18;
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, 0, obligationShares, borrowOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testObligationSharesBorrowMax() public {
        morphoV2.setTradingFee(id, 0.05e18, 0.001e18);
        uint256 obligationShares = 100 ether;
        lendOffer.startPrice = 0.9 ether;
        lendOffer.expiryPrice = 0.9 ether;

        uint256 expectedBuyerAssets = obligationShares * 0.9 ether / 1e18;
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(1e18, 1e18 + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, 0, obligationShares, lendOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }
}
