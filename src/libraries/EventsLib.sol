// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Seizure, Offer} from "../interfaces/IMorphoV2.sol";

library EventsLib {
    event Constructor(address indexed owner);

    event SetOwner(address indexed owner);
    event SetFeeSetter(address indexed feeSetter);
    event SetTradingFee(bytes32 indexed obligationId, uint256 fee);
    event SetTradingFeeRecipient(address indexed recipient);

    event Take(
        address indexed caller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address indexed taker,
        Offer offer
    );
    event Withdraw(
        address indexed caller,
        bytes32 indexed obligationId,
        address indexed onBehalf,
        uint256 obligationUnits,
        uint256 shares
    );
    event Repay(bytes32 indexed obligationId, address caller, uint256 obligationUnits, address indexed onBehalf);
    event SupplyCollateral(
        bytes32 indexed obligationId,
        address caller,
        address indexed collateral,
        uint256 assets,
        address indexed onBehalf
    );

    event WithdrawCollateral(
        bytes32 indexed obligationid,
        address caller,
        address indexed collateral,
        uint256 assets,
        address indexed onBehalf
    );

    event Liquidate(
        bytes32 indexed obligationId,
        address indexed caller,
        Seizure[] seizures,
        address indexed borrower,
        uint256 totalRepaid,
        uint256 badDebt
    );

    event Consume(address indexed user, bytes32 indexed group, uint256 amount);
    event ShuffleNonce(address indexed user, bytes32 nonce);
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);
}
