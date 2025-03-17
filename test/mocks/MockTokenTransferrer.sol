// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20TokenTransferrer, SendTokensInput, SendAndCallInput} from "@ictt/interfaces/IERC20TokenTransferrer.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MockTokenTransferrer is IERC20TokenTransferrer {
    bool public sendCalled;
    bytes32 public lastDestinationBlockchainID;
    address public lastRecipient;
    uint256 public lastAmount;
    address public immutable token;

    constructor(address _token) {
        token = _token;
    }

    function send(SendTokensInput calldata input, uint256 amount) external override {
        sendCalled = true;
        lastDestinationBlockchainID = input.destinationBlockchainID;
        lastRecipient = input.recipient;
        lastAmount = amount;

        // Transfer the tokens to simulate the cross-chain transfer
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function sendAndCall(SendAndCallInput calldata input, uint256 amount) external override {}

    function receiveTeleporterMessage(bytes32 sourceBlockchainID, address originSenderAddress, bytes calldata message)
        external
    {}
}
