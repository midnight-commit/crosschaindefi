// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {INativeTokenRemote} from "../lib/icm-contracts/contracts/ictt/TokenRemote/interfaces/INativeTokenRemote.sol";
import {SendAndCallInput} from "../lib/icm-contracts/contracts/ictt/interfaces/ITokenTransferrer.sol";
import {LendingInstructions} from "../src/interfaces/ICrossChainLender.sol";

contract SupplyCoqBorrowUsdc is Script {
    // Configure these values before running the script
    address constant TOKEN_REMOTE = 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98; // ERC20TokenHome address
    address constant TOKEN = 0x420FcA0121DC28039145009570975747295f2329; // The ERC20 token address
    bytes32 constant CCHAIN_BLOCKCHAIN_ID = 0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652;
    address constant COQ_TOKEN_HOME = 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2;
    address constant RECIPIENT_CONTRACT = 0xe61950e8a31E8e0eC786D93315C57DBcB184AD62;
    uint256 constant AMOUNT = 100e18; // Amount to send (adjust decimals as needed)
    uint256 constant REQUIRED_GAS_LIMIT = 0; // Adjust as needed

    address public constant QITOKEN_COQ = 0x0eBfebD41e1eA83Be5e911cDCd2730a0CCEE344d; // QiToken for COQ
    address public constant QITOKEN_USDC = 0x6B35Eb18BCA06bD7d66a428eeb45aC7d200C1e4E; // QiToken for USDC
    address public constant USDC_TOKEN_HOME = 0x97bBA61F61f2b0eEF60428947b990457f8eCb3a3;
    address public constant USDC_TOKEN_REMOTE = 0x00396774d1E5b1C2B175B0F0562f921887678771;
    bytes32 public constant COQ_BLOCKCHAIN_ID = 0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TESTER_PRIVATE_KEY");

        WarpMessengerMock warp = new WarpMessengerMock();
        vm.etch(0x0200000000000000000000000000000000000005, address(warp).code);

        vm.startBroadcast(deployerPrivateKey);

        LendingInstructions memory instructions = LendingInstructions({
            collateralQiToken: QITOKEN_COQ,
            borrowQiToken: QITOKEN_USDC,
            sourceTokenTransferrerAddress: USDC_TOKEN_HOME,
            destinationTokenTransferrerAddress: USDC_TOKEN_REMOTE,
            destinationBlockchainID: COQ_BLOCKCHAIN_ID
        });

        // 2. Create the SendTokensInput struct
        SendAndCallInput memory input = SendAndCallInput({
            destinationBlockchainID: CCHAIN_BLOCKCHAIN_ID,
            destinationTokenTransferrerAddress: COQ_TOKEN_HOME,
            recipientContract: RECIPIENT_CONTRACT,
            fallbackRecipient: vm.addr(deployerPrivateKey),
            recipientPayload: abi.encode(instructions),
            requiredGasLimit: 3_500_000,
            recipientGasLimit: 3_150_000,
            primaryFeeTokenAddress: address(0), // No fee token
            primaryFee: 0, // No fee
            secondaryFee: 0,
            multiHopFallback: address(0) // No multi-hop fallback for direct transfers
        });

        // 3. Call the send function using the interface
        INativeTokenRemote(TOKEN_REMOTE).sendAndCall{value: 1_000_000e18}(input);

        vm.stopBroadcast();
    }
}

// forge script --rpc-url $COQ_RPC_URL script/SupplyCoqBorrowUsdc.s.sol:SupplyCoqBorrowUsdc --skip-simulation --broadcast

contract WarpMessengerMock {
    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID) {}
}
