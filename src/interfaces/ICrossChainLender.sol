// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

struct LendingInstructions {
    address collateralQiToken;
    address borrowQiToken;
    address sourceTokenTransferrerAddress;
    bytes32 destinationBlockchainID;
    address destinationTokenTransferrerAddress;
}
