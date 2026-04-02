// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {ICallbacks} from "../interfaces/ICallbacks.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

contract IdleCallback is ICallbacks {
    address public immutable MIDNIGHT;
    mapping(address user => mapping(address token => uint256)) public balances;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function deposit(address token, uint256 amount) external {
        balances[msg.sender][token] += amount;
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    function withdraw(address token, uint256 amount) external {
        balances[msg.sender][token] -= amount;
        SafeTransferLib.safeTransfer(token, msg.sender, amount);
    }

    function onBuy(bytes32, Obligation memory obligation, address buyer, uint256 buyerAssets, uint256, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == MIDNIGHT);
        balances[buyer][obligation.loanToken] -= buyerAssets;
        IERC20(obligation.loanToken).approve(MIDNIGHT, buyerAssets);
        return CALLBACK_SUCCESS;
    }

    function onSell(bytes32, Obligation memory, address, uint256, uint256, bytes memory) external {}

    function onLiquidate(bytes32, Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}
