// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {console} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract LiquidationTest is BaseTest {
    ERC20 private loanToken;
    ERC20 private collateralToken;
    Oracle private oracle;
    uint256 private borrowerSK;
    address private borrower;
    uint256 private lenderSK;
    address private lender;
    address liquidator;
    uint256 liquidatorSK;
    Term[] private liquidationTerms;
    Seizure[] private s;

    function sortTokens(ERC20[] memory arr) internal pure returns (ERC20[] memory) {
        uint256 length = arr.length;
        for (uint256 i = 1; i < length; i++) {
            bytes20 key = bytes20((address(arr[i])));
            uint256 j = i - 1;
            while ((int256(j) >= 0) && (bytes20(address(arr[j])) > key)) {
                arr[j + 1] = arr[j];
                if (j == 0) {
                    break;
                }
                j--;
            }
            arr[j + (bytes20(address(arr[j])) > key ? 0 : 1)] = ERC20(address(key));
        }
        return arr;
    }

    function genTerm(uint256 n) internal returns (Term memory) {
        Collateral[] memory cs = new Collateral[](n);
        ERC20[] memory tokens = new ERC20[](n);

        for (uint256 i = 0; i < n; i++) {
            tokens[i] = new ERC20("collat", "c", 1 ether);
        }

        tokens = sortTokens(tokens);

        for (uint256 i = 0; i < n; i++) {
            ERC20 c = tokens[i];
            if (i < n - 1) {
                require(bytes20(address(tokens[i])) < bytes20(address(tokens[i + 1])));
            }
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
        terms.supplyCollateral(t, cs[0].token, remaining + 500, borrower);
        vm.stopPrank();

        return t;
    }

    function genSeizures() internal {
        s[0] = Seizure({collateralIndex: 0, repaidAmount: 100, seizedAssets: 0});
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
        (liquidator, liquidatorSK) = makeAddrAndKey("liquidator");

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
        s = new Seizure[](1);

        for (uint256 i = 0; i < 10; i++) {
            liquidationTerms[i] = genTerm(i + 1);
            mintBond(liquidationTerms[i].collaterals);
        }

        genSeizures();
    }

    function execLiquidation(uint256 n) public {
        loanToken.transfer(liquidator, 500);
        Term memory t = liquidationTerms[n - 1];
        vm.warp(block.timestamp + 50);
        Oracle(t.collaterals[0].oracle).setPrice(0.25e36);

        vm.prank(liquidator);
        uint256 gasBefore = gasleft();
        terms.liquidate(t, s, borrower, "0x0");
        uint256 gasUsed = gasBefore - gasleft();

        Oracle(t.collaterals[0].oracle).setPrice(1e36);
        emit log_named_uint("Gas used", gasUsed);

        bytes32 idT = keccak256(abi.encode(t));
        assertEq(terms.debtOf(borrower, idT), 900);
        assertEq(terms.withdrawable(idT), 100);

        assertEq(loanToken.balanceOf(address(terms)), 100);
        assertEq(loanToken.balanceOf(liquidator), 400);
        assertEq(ERC20(t.collaterals[0].token).balanceOf(liquidator), 460);
        vm.prank(borrower);
        loanToken.transfer(address(0), loanToken.balanceOf(borrower));
        vm.stopPrank();
        vm.prank(liquidator);
        loanToken.transfer(address(0), loanToken.balanceOf(liquidator));
        vm.stopPrank();
    }

    function testLiquidation1() public {
        execLiquidation(1);
    }

    function testLiquidation2() public {
        execLiquidation(2);
    }

    function testLiquidation3() public {
        execLiquidation(3);
    }

    function testLiquidation4() public {
        execLiquidation(4);
    }

    function testLiquidation5() public {
        execLiquidation(5);
    }

    function testLiquidation6() public {
        execLiquidation(6);
    }

    function testLiquidation7() public {
        execLiquidation(7);
    }

    function testLiquidation8() public {
        execLiquidation(8);
    }

    function testLiquidation9() public {
        execLiquidation(9);
    }

    function testLiquidation10() public {
        execLiquidation(10);
    }
}
