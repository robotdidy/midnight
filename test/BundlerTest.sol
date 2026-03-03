// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {TakeBundler} from "../src/periphery/TakeBundler.sol";
import {BaseTest} from "./BaseTest.sol";

contract BundlerTest is BaseTest {
    using UtilsLib for uint256;

    TakeBundler internal takeBundler;

    Obligation internal obligation;
    bytes20 internal id;
    Offer[] internal offers;

    function setUp() public override {
        super.setUp();

        takeBundler = new TakeBundler();

        // Set trading fees to max for all breakpoints.
        midnight.setTradingFeeRecipient(makeAddr("feeRecipient"));
        for (uint256 i; i <= 6; i++) {
            midnight.setDefaultTradingFee(address(loanToken), i, midnight.maxTradingFee(i));
        }

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        offers.push();
        offers[0].buy = true;
        offers[0].maker = lender;
        offers[0].obligation = obligation;
        offers[0].expiry = block.timestamp + 200;
        offers[0].tick = TICK_RANGE;

        offers.push();
        offers[1].buy = true;
        offers[1].maker = otherLender;
        offers[1].receiverIfMakerIsSeller = otherLender;
        offers[1].obligation = obligation;
        offers[1].expiry = block.timestamp + 200;
        offers[1].tick = TICK_RANGE;

        deal(address(loanToken), lender, type(uint256).max);
        deal(address(loanToken), otherLender, type(uint256).max);
    }

    function _authorizeBundler() internal {
        vm.prank(borrower);
        midnight.setIsAuthorized(address(takeBundler), true);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true);
    }

    function _sigsRootsProofs()
        internal
        view
        returns (Signature[] memory sigs, bytes32[] memory roots, bytes32[][] memory proofs)
    {
        sigs = new Signature[](2);
        sigs[0] = sig([offers[0]]);
        sigs[1] = sig([offers[1]]);

        roots = new bytes32[](2);
        roots[0] = root([offers[0]]);
        roots[1] = root([offers[1]]);

        proofs = new bytes32[][](2);
        proofs[0] = proof([offers[0]]);
        proofs[1] = proof([offers[1]]);
    }

    function testUnauthorizedShares() public {
        Offer[] memory _offers = new Offer[](1);
        _offers[0] = offers[0];

        Signature[] memory sigs = new Signature[](1);
        bytes32[] memory roots = new bytes32[](1);
        bytes32[][] memory proofs = new bytes32[][](1);
        uint256[] memory obligationShares = new uint256[](1);

        vm.prank(address(0xdead));
        vm.expectRevert("UNAUTHORIZED");
        takeBundler.bundleTakeShares(
            midnight, 100, borrower, address(0), hex"", address(0), obligationShares, _offers, sigs, roots, proofs
        );
    }

    function testBundleTakeShares(uint256 offerShares0, uint256 offerShares1) public {
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;
        (Signature[] memory sigs, bytes32[] memory roots, bytes32[][] memory proofs) = _sigsRootsProofs();

        uint256 units = 1000;
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        collateralize(obligation, borrower, units);

        uint256[] memory _obligationShares = new uint256[](2);
        _obligationShares[0] = offerShares0;
        _obligationShares[1] = offerShares1;

        _authorizeBundler();

        if (offerShares1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeShares(
                midnight, units, borrower, address(0), hex"", address(0), _obligationShares, offers, sigs, roots, proofs
            );

            assertEq(midnight.debtOf(id, borrower), units, "debt");

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeShares(
                midnight, units, borrower, address(0), hex"", address(0), _obligationShares, offers, sigs, roots, proofs
            );
        }
    }

    function testBundleTakeUnits(uint256 offerShares0, uint256 offerShares1) public {
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;
        (Signature[] memory sigs, bytes32[] memory roots, bytes32[][] memory proofs) = _sigsRootsProofs();

        uint256 units = 1000;
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        collateralize(obligation, borrower, units);

        uint256[] memory _obligationShares = new uint256[](2);
        _obligationShares[0] = offerShares0;
        _obligationShares[1] = offerShares1;

        _authorizeBundler();

        if (offerShares1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeUnits(
                midnight, units, borrower, address(0), hex"", address(0), _obligationShares, offers, sigs, roots, proofs
            );

            assertEq(midnight.debtOf(id, borrower), units, "debt");

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeUnits(
                midnight, units, borrower, address(0), hex"", address(0), _obligationShares, offers, sigs, roots, proofs
            );
        }
    }

    function testBundleTakeBuyerAssets(uint256 offerShares0, uint256 offerShares1) public {
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;
        (Signature[] memory sigs, bytes32[] memory roots, bytes32[][] memory proofs) = _sigsRootsProofs();

        uint256 units = 1000;
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        collateralize(obligation, borrower, units);

        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 targetBuyerAssets = units.mulDivDown(price, WAD);

        uint256[] memory _obligationShares = new uint256[](2);
        _obligationShares[0] = offerShares0;
        _obligationShares[1] = offerShares1;

        _authorizeBundler();

        if (offerShares1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeBuyerAssets(
                midnight,
                targetBuyerAssets,
                borrower,
                address(0),
                hex"",
                address(0),
                _obligationShares,
                offers,
                sigs,
                roots,
                proofs
            );

            assertEq(midnight.debtOf(id, borrower), units, "debt");

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeBuyerAssets(
                midnight,
                targetBuyerAssets,
                borrower,
                address(0),
                hex"",
                address(0),
                _obligationShares,
                offers,
                sigs,
                roots,
                proofs
            );
        }
    }

    function testBundleTakeSellerAssets(uint256 offerShares0, uint256 offerShares1) public {
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;
        (Signature[] memory sigs, bytes32[] memory roots, bytes32[][] memory proofs) = _sigsRootsProofs();

        uint256 units = 1000;
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        // Extra collateral headroom for the potential extra unit of debt.
        collateralize(obligation, borrower, units + 1);

        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 targetSellerAssets = units.mulDivDown(price - _tradingFee, WAD);

        uint256[] memory _obligationShares = new uint256[](2);
        _obligationShares[0] = offerShares0;
        _obligationShares[1] = offerShares1;

        _authorizeBundler();

        // Splitting across offers can cause up to 1 extra share of debt due to rounding.
        if (fromOffer0 >= units || offerShares1 >= units + 1 - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeSellerAssets(
                midnight,
                targetSellerAssets,
                borrower,
                address(0),
                hex"",
                address(0),
                _obligationShares,
                offers,
                sigs,
                roots,
                proofs
            );

            assertLe(midnight.debtOf(id, borrower), units + 1, "debt");

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeSellerAssets(
                midnight,
                targetSellerAssets,
                borrower,
                address(0),
                hex"",
                address(0),
                _obligationShares,
                offers,
                sigs,
                roots,
                proofs
            );
        }
    }
}
