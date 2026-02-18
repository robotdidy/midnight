// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface ILenderGate {
    function canLend(address account) external view returns (bool);
}

interface IBorrowerGate {
    function canBorrow(address account) external view returns (bool);
}

interface ILiquidatorGate {
    function canLiquidate(address account) external view returns (bool);
}
