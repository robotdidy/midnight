// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {TakeBundler} from "../src/periphery/TakeBundler.sol";
import {Offer, Obligation, Signature, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";

contract BundlerTest is BaseTest {
    TakeBundler internal takeBundler;
    Obligation internal obligation;
    bytes20 internal id;
    Offer internal lenderOffer;
    Offer internal otherLenderOffer;

    function setUp() public override {
        super.setUp();
        takeBundler = new TakeBundler();

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
        lenderOffer.obligationShares = 500;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        otherLenderOffer.buy = true;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.receiverIfMakerIsSeller = otherLender;
        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = TICK_RANGE;

        deal(address(loanToken), lender, type(uint256).max);
        deal(address(loanToken), otherLender, type(uint256).max);
    }

    function testBundler() public {
        Offer[] memory offers = new Offer[](2);
        offers[0] = lenderOffer;
        offers[1] = otherLenderOffer;

        Signature[] memory sigs = new Signature[](2);
        sigs[0] = sig([offers[0]]);
        sigs[1] = sig([offers[1]]);

        bytes32[] memory roots = new bytes32[](2);
        roots[0] = root([offers[0]]);
        roots[1] = root([offers[1]]);

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = proof([offers[0]]);
        proofs[1] = proof([offers[1]]);

        uint256 units = 1000;
        collateralize(obligation, borrower, units);

        vm.prank(borrower);
        morphoV2.setIsAuthorized(address(takeBundler), true);

        vm.prank(borrower);
        morphoV2.setIsAuthorized(address(this), true);

        vm.prank(borrower);
        takeBundler.bundleTake(morphoV2, units, borrower, address(0), hex"", address(0), offers, sigs, roots, proofs);

        assertEq(morphoV2.debtOf(id, borrower), units);
    }
}
