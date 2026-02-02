// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

/// @dev SStore2 is a contract that stores data in the bytecode, to save gas on read and write operations.
contract SStore2 {
    constructor(bytes memory data) {
        assembly ("memory-safe") {
            return(add(data, 0x20), mload(data))
        }
    }
}
