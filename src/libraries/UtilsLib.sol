// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library UtilsLib {
    /// @dev Returns true if at most one of `x` and `y` is nonzero.
    function atMostOneNonZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := gt(add(iszero(x), iszero(y)), 0)
        }
    }

    /// @dev Returns true if at most one of `x`, `y`, `z` is nonzero.
    function atMostOneNonZero(uint256 a, uint256 b, uint256 c) internal pure returns (bool z) {
        assembly {
            z := gt(add(add(iszero(a), iszero(b)), iszero(c)), 1)
        }
    }

    /// @dev Returns true if at most one of `a`, `b`, `c`, `d` is nonzero.
    function atMostOneNonZero(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (bool z) {
        assembly {
            z := gt(add(add(add(iszero(a), iszero(b)), iszero(c)), iszero(d)), 2)
        }
    }

    /// @dev Returns min(a, b).
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns (`x` * `y`) / `d` rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (`x` * `y`) / `d` rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns hash(... hash(leafHash, proof[0]), ..., proof[n]) == root.
    /// @dev Hash sorts the inputs lexicographically.
    function isLeaf(bytes32 root, bytes32 leafHash, bytes32[] memory proof) internal pure returns (bool) {
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = keccak256(sort(currentHash, proof[i]));
        }
        return currentHash == root;
    }

    /// @dev Returns the concatenation of x and y, sorted lexicographically.
    function sort(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        return x < y ? abi.encodePacked(x, y) : abi.encodePacked(y, x);
    }

    function wExp(int256 x) internal pure returns (uint256) {
        if (x < 0) {
            return 1e36 / wExp(-x);
        } else {
            int256 ln2 = 0.693147180559945309e18;
            int256 q = (x + ln2 / 2) / ln2;
            int256 r = x - q * ln2;
            int256 secondTerm = r * r / (2 * 1e18);
            int256 thirdTerm = secondTerm * r / (3 * 1e18);
            int256 expR = 1e18 + r + secondTerm + thirdTerm;
            // forge-lint: disable-next-item(unsafe-typecast)
            // - q is positive because x is positive in this branch
            // - expR is positive?? (TODO)
            return uint256(expR) << uint256(q);
        }
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "uint256 overflows uint128");
        // forge-lint: disable-next-item(unsafe-typecast) as x is less than type(uint128).max
        return uint128(x);
    }
}
