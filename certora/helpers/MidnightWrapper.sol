// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {
    WAD,
    ORACLE_PRICE_SCALE
} from "../../src/libraries/ConstantsLib.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {BorrowerState, Collateral, Obligation} from "../../src/interfaces/IMidnight.sol";
import {Midnight} from "../../src/Midnight.sol";

contract MidnightWrapper is Midnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    function preciseMaxDebt(address borrower, Obligation memory obligation, bytes20 id) external view returns (uint256) {
        BorrowerState storage _borrowerState = borrowerState[id][borrower];
        uint256 maxDebt;
        uint256 bitmap = _borrowerState.activatedCollaterals;
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            if ((bitmap & (1 << i)) != 0) {
                Collateral memory collateral = obligation.collaterals[i];
                uint256 price = IOracle(collateral.oracle).price();
                maxDebt += collateralOf[id][borrower][i].mulDivDown(price * collateral.lltv, ORACLE_PRICE_SCALE * WAD);
            }
        }
        return maxDebt;
    }
}
