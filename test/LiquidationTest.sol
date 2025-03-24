// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {console} from "../lib/forge-std/src/Test.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract LiquidationTest is BaseTest {
    ERC20 private loanToken;
    uint256 private borrowerSK;
    address private borrower;
    uint256 private lenderSK;
    address private lender;
    address liquidator;
    Term[] private liquidationTerms;
    Seizure[][] private s;

    function genTerm(uint256 n) internal returns (Term memory) {
        Collateral[] memory cs = new Collateral[](n);
        ERC20[] memory tokens = new ERC20[](n);

        for (uint256 i = 0; i < n; i++) {
            tokens[i] = new ERC20("collat", "c", 1 ether);
        }

        tokens = sortTokens(tokens);

        for (uint256 i = 0; i < n; i++) {
            ERC20 c = tokens[i];
            Oracle o = new Oracle();
            c.transfer(borrower, 1 ether);
            cs[i] = Collateral({token: address(tokens[i]), lltv: 0.75e18, oracle: address(o)});

            vm.startPrank(borrower);
            c.approve(address(terms), type(uint256).max);
            vm.stopPrank();
        }

        Term memory t = Term(address(loanToken), cs, block.timestamp + 100);

        loanToken.transfer(lender, 1000);

        vm.startPrank(borrower);
        uint256 remaining = 840;
        uint256 dealt;
        for (uint256 i = 1; i < n; i++) {
            dealt += remaining / (n - 1);
            terms.supplyCollateral(t, cs[i].token, remaining / (n - 1), borrower);
        }
        // The collateral in position 0 is used to make the position liquidatable.
        terms.supplyCollateral(t, cs[0].token, remaining + 500, borrower);
        vm.stopPrank();

        return t;
    }

    function mintBond(Collateral[] memory cs) internal {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 1000,
            loanToken: address(loanToken),
            collaterals: cs,
            maturity: block.timestamp + 100,
            price: 990
        });

        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 1000,
            loanToken: address(loanToken),
            collaterals: cs,
            maturity: block.timestamp + 100,
            price: 990
        });

        Signature memory lendSig = _signOffer(lendOffer, lenderSK);
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        terms.MATCH(lendOffer, lendSig, borrowOffer, borrowSig);
    }

    function setUp() public override {
        super.setUp();
        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");
        liquidator = makeAddr("liquidator");

        loanToken = new ERC20("loan", "loan", 1 ether);
        loanToken.transfer(lender, 99);
        loanToken.transfer(borrower, 1);

        vm.prank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);
        vm.stopPrank();

        liquidationTerms = new Term[](10);
        s = new Seizure[][](10);

        for (uint256 i = 0; i < 10; i++) {
            liquidationTerms[i] = genTerm(i + 1);
            mintBond(liquidationTerms[i].collaterals);
            s[i] = new Seizure[](i + 1);
            s[i][0] = Seizure({collateralIndex: 0, repaidAmount: 100, seizedAssets: 0});
            for (uint256 k = 1; k < i + 1; k++) {
                s[i][k] = Seizure({collateralIndex: k, repaidAmount: 0, seizedAssets: 93});
            }
        }
    }

    function execLiquidation(uint256 k, uint256 n) public {
        loanToken.transfer(liquidator, 1000);
        Term memory t = liquidationTerms[n - 1];
        vm.warp(block.timestamp + 50);
        Oracle(t.collaterals[0].oracle).setPrice(0.25e36);

        vm.prank(liquidator);
        uint256 gasBefore = gasleft();
        if (n < 10) {
            terms.liquidate(t, s[0], borrower, "0x0");
        } else {
            terms.liquidate(t, s[k - 1], borrower, "0x0");
        }
        uint256 gasUsed = gasBefore - gasleft();

        Oracle(t.collaterals[0].oracle).setPrice(1e36);
        emit log_named_uint("Gas used", gasUsed);

        bytes32 idT = keccak256(abi.encode(t));
        // assertEq(terms.debtOf(borrower, idT), 900);
        //assertEq(terms.withdrawable(idT), 100);

        //assertEq(loanToken.balanceOf(address(terms)), 100);
        //assertEq(loanToken.balanceOf(liquidator), 400);
        assertEq(ERC20(t.collaterals[0].token).balanceOf(liquidator), 460);
        vm.prank(borrower);
        loanToken.transfer(address(0), loanToken.balanceOf(borrower));
        vm.stopPrank();
        vm.prank(liquidator);
        loanToken.transfer(address(0), loanToken.balanceOf(liquidator));
        vm.stopPrank();
    }

    function testLiquidation1Collat() public {
        execLiquidation(1, 1);
    }

    function testLiquidation2Collats() public {
        execLiquidation(1, 2);
    }

    function testLiquidation3Collats() public {
        execLiquidation(1, 3);
    }

    function testLiquidation4Collats() public {
        execLiquidation(1, 4);
    }

    function testLiquidation5Collats() public {
        execLiquidation(1, 5);
    }

    function testLiquidation6Collats() public {
        execLiquidation(1, 6);
    }

    function testLiquidation7Collats() public {
        execLiquidation(1, 7);
    }

    function testLiquidation8Collats() public {
        execLiquidation(1, 8);
    }

    function testLiquidation9Collats() public {
        execLiquidation(1, 9);
    }

    function testLiquidation10Collats1() public {
        execLiquidation(1, 10);
    }

    function testLiquidation10Collats2() public {
        execLiquidation(2, 10);
    }

    function testLiquidation10Collats3() public {
        execLiquidation(3, 10);
    }

    function testLiquidation10Collats4() public {
        execLiquidation(4, 10);
    }

    function testLiquidation10Collats5() public {
        execLiquidation(5, 10);
    }

    function testLiquidation10Collats6() public {
        execLiquidation(6, 10);
    }

    function testLiquidation10Collats7() public {
        execLiquidation(7, 10);
    }

    function testLiquidation10Collats8() public {
        execLiquidation(8, 10);
    }

    function testLiquidation10Collats9() public {
        execLiquidation(9, 10);
    }

    function testLiquidation10Collats10() public {
        execLiquidation(10, 10);
    }
}
