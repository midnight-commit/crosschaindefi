// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

enum LendingAction {
    Borrow,
    Repay
}

struct BaseLendingInstructions {
    address sourceTokenTransferrerAddress;
    address destinationTokenTransferrerAddress;
    bytes32 destinationBlockchainID;
    uint8 riskFactor;
    bytes protocolData;
    LendingAction action;
}

interface ICrossChainLender {
    function positionHolders(address) external view returns (address);
}
