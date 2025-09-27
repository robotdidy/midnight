// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract SettersTest is BaseTest {
    function testInitialOwner() public view {
        assertEq(terms.owner(), address(this), "deployer should be initial owner");
    }

    function testSetOwnerSuccess(address rdm) public {
        terms.setOwner(rdm);
        assertEq(terms.owner(), rdm, "owner should be transferred");
    }

    function testSetOwnerOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        terms.setOwner(makeAddr("newOwner"));
    }

    function testSetTradingFeeSuccess(uint256 feePct) public {
        vm.assume(feePct <= 1e18);
        terms.setTradingFee(address(loanToken), feePct);
        assertEq(terms.tradingFeePct(address(loanToken)), feePct);
    }

    function testSetTradingFeeOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        terms.setTradingFee(address(loanToken), 0.1e18);
    }

    function testSetTradingFeeTooHigh(uint256 feePct) public {
        vm.assume(feePct > 1e18);
        vm.expectRevert("Fee too high");
        terms.setTradingFee(address(loanToken), feePct);
    }

    function testSetTradingFeeRecipientSuccess(address recipient) public {
        terms.setTradingFeeRecipient(address(loanToken), recipient);
        assertEq(terms.tradingFeeRecipient(address(loanToken)), recipient, "recipient set");
    }

    function testSetTradingFeeRecipientOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        terms.setTradingFeeRecipient(address(loanToken), makeAddr("newRecipient"));
    }
}
