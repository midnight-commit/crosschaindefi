// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseLendingInstructions} from "./ICrossChainLender.sol";

/**
 * @title IAaveLender
 * @notice Interface for the Aave V3 lending protocol implementation
 */
struct AaveLendingInstructions {
    // Aave-specific parameters
    address poolAddress; // The address of the Aave V3 lending pool
    address collateralAsset; // The underlying asset to use as collateral
    address borrowAsset; // The underlying asset to borrow
    uint16 referralCode; // Optional referral code for Aave (usually 0)
}
