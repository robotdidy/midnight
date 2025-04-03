// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Seizure} from "./ITerms.sol";

interface IMorphoLiquidationCallback {
    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external;
}
