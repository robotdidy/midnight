// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMorphoV2, Obligation} from "./interfaces/IMorphoV2.sol";

contract ObligationDeployer {
    constructor() {
        Obligation memory obligation = IMorphoV2(msg.sender).obligationBeingCreated();
        bytes memory encodedObligation = abi.encode(obligation);

        assembly ("memory-safe") {
            return(add(encodedObligation, 0x20), mload(encodedObligation))
        }
    }
}
