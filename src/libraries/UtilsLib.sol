// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {TICK_RANGE, LN_ONE_PLUS_DELTA} from "./ConstantsLib.sol";

library UtilsLib {
    using UtilsLib for uint256;

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

    /// @dev Returns (`x` + `d` - 1) / `d` rounded up, without checking for overflow.
    function divUpUnchecked(uint256 x, uint256 d) internal pure returns (uint256) {
        unchecked {
            return (x + (d - 1)) / d;
        }
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
        unchecked {
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
                // - q is non-negative because x is non-negative in this branch
                // - expR is positive because |r| < ln2 < 1e18 and |secondTerm| > |thirdTerm|
                return uint256(expR) << uint256(q);
            }
        }
    }

    function tickToPrice(uint256 tick) internal pure returns (uint256) {
        unchecked {
            // forge-lint: disable-next-item(unsafe-typecast)
            return uint256(1e36)
                    .divUpUnchecked(1e18 + wExp(LN_ONE_PLUS_DELTA * (int256(TICK_RANGE / 2) - int256(tick))))
                    .divUpUnchecked(1e13) * 1e13;
        }
    }

    /// @dev Returns the lowest tick with a higher price.
    function priceToTick(uint256 price) internal pure returns (uint256) {
        uint256 low = 0;
        uint256 high = TICK_RANGE;
        while (low != high) {
            unchecked {
                uint256 mid = (low + high) / 2;
                if (tickToPrice(mid) < price) low = mid + 1;
                else high = mid;
            }
        }
        return low;
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "uint256 overflows uint128");
        // forge-lint: disable-next-item(unsafe-typecast) as x is less than type(uint128).max
        return uint128(x);
    }
}
