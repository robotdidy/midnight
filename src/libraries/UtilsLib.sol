// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library UtilsLib {
    /// @dev Returns true if there is exactly one zero among `x` and `y`.
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := xor(iszero(x), iszero(y))
        }
    }

    /// @dev Returns true if at most one of `a`, `b`, `c` is nonzero.
    function atMostOneNonZero(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (bool z) {
        assembly {
            z := gt(add(add(add(iszero(a), iszero(b)), iszero(c)), iszero(d)), 1)
        }
    }

    /// @dev Returns min(a, b).
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }
}
