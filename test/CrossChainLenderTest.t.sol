// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import "../src/CrossChainLender.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {LendingInstructions} from "../src/interfaces/ICrossChainLender.sol";

contract CrossChainLenderTest is Test {
    // Avalanche Mainnet addresses
    address public constant COMPTROLLER = 0xD7c4006d33DA2A0A8525791ed212bbCD7Aca763F;
    address public constant QITOKEN_COQ = 0x0eBfebD41e1eA83Be5e911cDCd2730a0CCEE344d; // QiToken for COQ
    address public constant QITOKEN_USDC = 0x6B35Eb18BCA06bD7d66a428eeb45aC7d200C1e4E; // QiToken for USDC
    address public constant COQ = 0x420FcA0121DC28039145009570975747295f2329; // COQ token
    address public constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // USDC token

    address public constant USDC_TOKEN_HOME = 0x97bBA61F61f2b0eEF60428947b990457f8eCb3a3;
    address public constant USDC_TOKEN_REMOTE = 0x00396774d1E5b1C2B175B0F0562f921887678771;
    bytes32 public constant DESTINATION_BLOCKCHAIN_ID =
        0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33;

    // Test addresses
    address constant ALICE = address(0x1);
    uint256 constant COQ_AMOUNT = 1_000_000 ether;

    CrossChainLender lender;

    function setUp() public {
        // Deploy the contract
        lender = new CrossChainLender(COMPTROLLER);

        // Setup test users
        vm.label(ALICE, "Alice");
        vm.label(address(lender), "CrossChainLender");
    }

    function test_SupplyCollateralAndBorrow() public {
        uint256 collateralAmount = COQ_AMOUNT; // 10 AVAX

        // Create lending instructions
        LendingInstructions memory instructions = LendingInstructions({
            collateralQiToken: QITOKEN_COQ,
            borrowQiToken: QITOKEN_USDC,
            sourceTokenTransferrerAddress: USDC_TOKEN_HOME,
            destinationTokenTransferrerAddress: USDC_TOKEN_REMOTE,
            destinationBlockchainID: DESTINATION_BLOCKCHAIN_ID
        });

        // Encode the instructions
        bytes memory payload = abi.encode(instructions);

        deal(COQ, address(this), COQ_AMOUNT);
        IERC20(COQ).approve(address(lender), collateralAmount);

        // Call receiveTokens directly (simulating cross-chain transfer)
        lender.receiveTokens(
            bytes32(0), // messageID
            address(0), // sourceTokenTransferrer
            ALICE, // originSenderAddress
            COQ, // token
            collateralAmount, // amount
            payload // encoded instructions
        );

        // Verify ALICE received qiAVAX tokens
        assertTrue(IERC20(QITOKEN_COQ).balanceOf(ALICE) > 0, "No qiCOQ tokens received");

        // Verify contract has no remaining COQ balance
        assertEq(IERC20(COQ).balanceOf(address(lender)), 0, "Contract should have no COQ");

        // Verify the borrowed USDC was sent cross-chain (mock call was made)
        // In a real scenario, we'd verify the TokenTransferrer interaction
    }
}
