// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract SettersTest is BaseTest {
    function testInitialOwner() public view {
        assertEq(morphoV2.owner(), address(this), "deployer should be initial owner");
    }

    function testSetOwnerSuccess(address rdm) public {
        morphoV2.setOwner(rdm);
        assertEq(morphoV2.owner(), rdm, "owner should be transferred");
    }

    function testSetOwnerOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setOwner(makeAddr("newOwner"));
    }

    function testSetTradingFeeSuccess(uint256 fee) public {
        vm.assume(fee <= 1e18);
        morphoV2.setTradingFee(address(loanToken), fee);
        assertEq(morphoV2.tradingFee(address(loanToken)), fee);
    }

    function testSetTradingFeeOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setTradingFee(address(loanToken), 0.1e18);
    }

    function testSetTradingFeeTooHigh(uint256 fee) public {
        vm.assume(fee > 1e18);
        vm.expectRevert("Fee too high");
        morphoV2.setTradingFee(address(loanToken), fee);
    }

    function testSetTradingFeeRecipientSuccess(address recipient) public {
        morphoV2.setTradingFeeRecipient(recipient);
        assertEq(morphoV2.tradingFeeRecipient(), recipient, "recipient set");
    }

    function testSetTradingFeeRecipientOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setTradingFeeRecipient(makeAddr("newRecipient"));
    }
}
