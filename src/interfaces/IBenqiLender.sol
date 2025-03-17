// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseLendingInstructions} from "./ICrossChainLender.sol";

struct BenqiLendingInstructions {
    address collateralQiToken;
    address borrowQiToken;
}
