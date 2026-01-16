// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

/// @title FeeLib
/// @notice Library for packing/unpacking trading fees in a single uint256.
/// @dev Storage layout:
///   - Bit 0: activated flag
///   - Bits 1-144: 6 trading fees packed (24 bits each)
///   - Fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d
/// @dev Fees are stored divided by 1e12 to fit in 24 bits.
library FeeLib {
    uint256 internal constant FEE_PRECISION = 1e12;
    uint256 internal constant FEE_BITS = 24;
    uint256 internal constant FEE_MASK = 0xFFFFFF;
    uint256 internal constant ACTIVATED_MASK = 1;

    /// @dev Returns whether the fee storage is activated.
    function isActivated(uint256 feeStorage) internal pure returns (bool) {
        return feeStorage & ACTIVATED_MASK != 0;
    }

    /// @dev Returns the fee at the given index, scaled back to WAD precision.
    function getFee(uint256 feeStorage, uint256 index) internal pure returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(uint24(feeStorage >> (1 + index * FEE_BITS))) * FEE_PRECISION;
    }

    /// @dev Returns the updated packed fee storage value.
    function setFee(uint256 feeStorage, uint256 index, uint256 fee, bool activated) internal pure returns (uint256) {
        uint256 shift = 1 + index * FEE_BITS;
        uint256 cleared = feeStorage & ~(FEE_MASK << shift) & ~ACTIVATED_MASK;
        uint256 packedFee = (fee / FEE_PRECISION) << shift;
        uint256 flag = activated ? ACTIVATED_MASK : 0;
        return cleared | packedFee | flag;
    }
}
