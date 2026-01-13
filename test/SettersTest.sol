// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

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

    function testSetFeeSetterSuccess(address feeSetter) public {
        morphoV2.setFeeSetter(feeSetter);
        assertEq(morphoV2.feeSetter(), feeSetter);
    }

    function testSetFeeSetterOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setFeeSetter(makeAddr("newFeeSetter"));
    }

    function testSetTradingFeeSuccess(
        bytes32 id,
        uint256 postMaturityFee,
        uint256 zeroDaysFee,
        uint256 oneDaysFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, WAD);
        zeroDaysFee = bound(zeroDaysFee, 0, WAD);
        oneDaysFee = bound(oneDaysFee, 0, WAD);
        sevenDaysFee = bound(sevenDaysFee, 0, WAD);
        thirtyDaysFee = bound(thirtyDaysFee, 0, WAD);
        ninetyDaysFee = bound(ninetyDaysFee, 0, WAD);

        morphoV2.setObligationTradingFee(id, 0, postMaturityFee);
        morphoV2.setObligationTradingFee(id, 1, zeroDaysFee);
        morphoV2.setObligationTradingFee(id, 2, oneDaysFee);
        morphoV2.setObligationTradingFee(id, 3, sevenDaysFee);
        morphoV2.setObligationTradingFee(id, 4, thirtyDaysFee);
        morphoV2.setObligationTradingFee(id, 5, ninetyDaysFee);

        assertEq(morphoV2.obligationTradingFee(id, 0), postMaturityFee / 1e9 * 1e9, "post maturity trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 1), zeroDaysFee / 1e9 * 1e9, "zero days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 1 days), oneDaysFee / 1e9 * 1e9, "one days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 7 days), sevenDaysFee / 1e9 * 1e9, "seven days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 30 days), thirtyDaysFee / 1e9 * 1e9, "thirty days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 90 days), ninetyDaysFee / 1e9 * 1e9, "ninety days trading fee");
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setObligationTradingFee(id, 0, 0);
    }

    function testSetTradingFeeZeroDaysTooHigh(bytes32 id, uint256 tradingFeeTooHigh) public {
        tradingFeeTooHigh = bound(tradingFeeTooHigh, WAD + 1, 2 * WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setObligationTradingFee(id, 0, tradingFeeTooHigh);
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

    // Default trading fee tests

    function testUnsetDefaultFeeReturnsZero() public {
        address randomToken = makeAddr("randomToken");
        assertEq(morphoV2.defaultTradingFee(randomToken, 0), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 1 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 7 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 30 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 90 days), 0, "unset default fee should be 0");
    }

    function testSetDefaultTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 zeroDaysFee,
        uint256 oneDaysFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, WAD);
        zeroDaysFee = bound(zeroDaysFee, 0, WAD);
        oneDaysFee = bound(oneDaysFee, 0, WAD);
        sevenDaysFee = bound(sevenDaysFee, 0, WAD);
        thirtyDaysFee = bound(thirtyDaysFee, 0, WAD);
        ninetyDaysFee = bound(ninetyDaysFee, 0, WAD);

        morphoV2.setDefaultTradingFee(loanToken, 0, postMaturityFee);
        morphoV2.setDefaultTradingFee(loanToken, 1, zeroDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 2, oneDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 3, sevenDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 4, thirtyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 5, ninetyDaysFee);

        assertEq(morphoV2.defaultTradingFee(loanToken, 0), postMaturityFee / 1e9 * 1e9, "post maturity fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 1), zeroDaysFee / 1e9 * 1e9, "zero days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 1 days), oneDaysFee / 1e9 * 1e9, "one days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 7 days), sevenDaysFee / 1e9 * 1e9, "seven days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 30 days), thirtyDaysFee / 1e9 * 1e9, "thirty days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 90 days), ninetyDaysFee / 1e9 * 1e9, "ninety days default fee");
    }

    function testSetDefaultTradingFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setDefaultTradingFee(loanToken, 0, 0);
    }

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh) public {
        feeTooHigh = bound(feeTooHigh, WAD + 1, 2 * WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setDefaultTradingFee(loanToken, 0, feeTooHigh);
    }

    function testDefaultTradingFeeTTMBuckets() public {
        address loanToken = makeAddr("loanToken");

        morphoV2.setDefaultTradingFee(loanToken, 0, 0.001e18);
        morphoV2.setDefaultTradingFee(loanToken, 1, 0.002e18);
        morphoV2.setDefaultTradingFee(loanToken, 2, 0.003e18);
        morphoV2.setDefaultTradingFee(loanToken, 3, 0.004e18);
        morphoV2.setDefaultTradingFee(loanToken, 4, 0.005e18);
        morphoV2.setDefaultTradingFee(loanToken, 5, 0.006e18);

        // Test bucket 0: post maturity
        assertEq(morphoV2.defaultTradingFee(loanToken, 0), 0.001e18, "0 seconds");

        // Test bucket 1: < 1 day
        assertEq(morphoV2.defaultTradingFee(loanToken, 1), 0.002e18, "1 second");
        assertEq(morphoV2.defaultTradingFee(loanToken, 1 hours), 0.002e18, "1 hour");
        assertEq(morphoV2.defaultTradingFee(loanToken, 1 days - 1), 0.002e18, "just under 1 day");

        // Test bucket 2: < 7 day
        assertEq(morphoV2.defaultTradingFee(loanToken, 1 days), 0.003e18, "1 day");
        assertEq(morphoV2.defaultTradingFee(loanToken, 3 days), 0.003e18, "3 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 7 days - 1), 0.003e18, "just under 7 days");

        // Test bucket 3: < 30 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 7 days), 0.004e18, "7 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 14 days), 0.004e18, "14 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 30 days - 1), 0.004e18, "just under 30 days");

        // Test bucket 4: < 90 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 30 days), 0.005e18, "30 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 60 days), 0.005e18, "60 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 90 days - 1), 0.005e18, "just under 90 days");

        // Test bucket 5: >= 90 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 90 days), 0.006e18, "90 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 180 days), 0.006e18, "180 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 365 days), 0.006e18, "365 days");
    }
}
