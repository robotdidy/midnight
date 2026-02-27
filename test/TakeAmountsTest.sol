// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {TakeAmountsLib} from "../src/periphery/TakeAmountsLib.sol";

contract TakeAmountsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes20 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;

    uint256 internal initialUnits;
    uint256 internal initialShares;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligationShares = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        createBadDebt(obligation); // to create non trivial shares <=> units conversion.

        initialUnits = morphoV2.totalUnits(id);
        initialShares = morphoV2.totalShares(id);
    }

    // offer.buy = false: buyer = taker (lender), seller = maker (borrower).
    // sellerPrice = price, buyerPrice = price + fee.

    function testUnitsToShares(uint256 targetUnits, uint256 tick, uint256 fee0, uint256 fee1) public {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetUnits = bound(targetUnits, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        uint256 shares = TakeAmountsLib.unitsToShares(targetUnits, initialUnits, initialShares, true);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, targetUnits);
        borrowerOffer.tick = tick;

        (,, uint256 obligationUnits,) = take(shares, lender, borrowerOffer);

        assertEq(obligationUnits, targetUnits, "e2e units");
    }

    function testBuyerAssetsToShares(uint256 targetBuyerAssets, uint256 tick, uint256 fee0, uint256 fee1) public {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        deal(address(loanToken), lender, type(uint256).max);
        borrowerOffer.tick = tick;
        // borrowerOffer.buy = false → buyerPrice = price + fee.
        uint256 buyerPrice = TickLib.tickToPrice(tick) + morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 shares =
            TakeAmountsLib.buyerAssetsToShares(targetBuyerAssets, initialUnits, initialShares, buyerPrice, true);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));

        (uint256 buyerAssets,,,) = take(shares, lender, borrowerOffer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToShares(uint256 targetSellerAssets, uint256 tick, uint256 fee0, uint256 fee1) public {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        deal(address(loanToken), lender, type(uint256).max);
        borrowerOffer.tick = tick;
        // borrowerOffer.buy = false → sellerPrice = price.
        uint256 sellerPrice = TickLib.tickToPrice(tick);
        uint256 shares =
            TakeAmountsLib.sellerAssetsToShares(targetSellerAssets, initialUnits, initialShares, sellerPrice, true);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));

        (, uint256 sellerAssets,,) = take(shares, lender, borrowerOffer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // offer.buy = true: buyer = maker (lender), seller = taker (borrower).
    // sellerPrice = offerPrice - fee, buyerPrice = offerPrice.

    function testUnitsToSharesBuyOffer(uint256 targetUnits, uint256 tick, uint256 fee0, uint256 fee1) public {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetUnits = bound(targetUnits, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        uint256 _tradingFee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        vm.assume(TickLib.tickToPrice(tick) >= _tradingFee);
        uint256 shares = TakeAmountsLib.unitsToShares(targetUnits, initialUnits, initialShares, true);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, targetUnits);
        lenderOffer.tick = tick;

        (,, uint256 obligationUnits,) = take(shares, borrower, lenderOffer);

        assertEq(obligationUnits, targetUnits, "e2e units");
    }

    function testBuyerAssetsToSharesBuyOffer(uint256 targetBuyerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        uint256 _tradingFee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 buyerPrice = TickLib.tickToPrice(tick);
        vm.assume(buyerPrice >= _tradingFee);
        deal(address(loanToken), lender, type(uint256).max);
        lenderOffer.tick = tick;
        uint256 shares =
            TakeAmountsLib.buyerAssetsToShares(targetBuyerAssets, initialUnits, initialShares, buyerPrice, true);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));

        (uint256 buyerAssets,,,) = take(shares, borrower, lenderOffer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToSharesBuyOffer(uint256 targetSellerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        uint256 _tradingFee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        vm.assume(TickLib.tickToPrice(tick) > _tradingFee);
        deal(address(loanToken), lender, type(uint256).max);
        lenderOffer.tick = tick;
        uint256 sellerPrice = TickLib.tickToPrice(tick) - _tradingFee;
        uint256 shares =
            TakeAmountsLib.sellerAssetsToShares(targetSellerAssets, initialUnits, initialShares, sellerPrice, true);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));

        (, uint256 sellerAssets,,) = take(shares, borrower, lenderOffer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }
}
