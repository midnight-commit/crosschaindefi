// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {IERC20TokenTransferrer} from "../lib/icm-contracts/contracts/ictt/interfaces/IERC20TokenTransferrer.sol";
import {SendAndCallInput} from "../lib/icm-contracts/contracts/ictt/interfaces/ITokenTransferrer.sol";
import {BaseLendingInstructions, LendingAction, ICrossChainLender} from "../src/interfaces/ICrossChainLender.sol";
import {AaveLendingInstructions} from "../src/interfaces/IAaveLender.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract RepayUsdcWithdrawAvax is Script {
    bytes32 constant CCHAIN_BLOCKCHAIN_ID = 0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652;
    bytes32 constant COQ_BLOCKCHAIN_ID = 0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33;
    address constant LENDER_CONTRACT = 0x5a29042Dfba51e2b794125e5d9c96BE8bC6FAD23;

    address constant WAVAX_TOKEN_HOME = 0x30CdA6AF61c3A07ca81909699C85307DEF4398E5;
    address constant WAVAX_TOKEN_REMOTE = 0x28aF629a9F3ECE3c8D9F0b7cCf6349708CeC8cFb;
    address constant USDC_TOKEN_HOME = 0x97bBA61F61f2b0eEF60428947b990457f8eCb3a3;
    address constant USDC_TOKEN_REMOTE = 0x00396774d1E5b1C2B175B0F0562f921887678771;

    address constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant WRAPPED_AVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant USDC_VARIABLE_DEBT_TOKEN = 0xFCCf3cAbbe80101232d343252614b6A3eE81C989;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TESTER_PRIVATE_KEY");

        WarpMessengerMock warp = new WarpMessengerMock();
        vm.etch(0x0200000000000000000000000000000000000005, address(warp).code);

        uint256 forkIdCoq = vm.activeFork();

        AaveLendingInstructions memory aaveInstructions = AaveLendingInstructions({
            poolAddress: AAVE_POOL,
            collateralAsset: WRAPPED_AVAX,
            borrowAsset: USDC,
            referralCode: 0
        });

        BaseLendingInstructions memory instructions = BaseLendingInstructions({
            sourceTokenTransferrerAddress: WAVAX_TOKEN_HOME,
            destinationTokenTransferrerAddress: WAVAX_TOKEN_REMOTE,
            destinationBlockchainID: COQ_BLOCKCHAIN_ID,
            riskFactor: 0,
            protocolData: abi.encode(aaveInstructions),
            action: LendingAction.Repay
        });

        SendAndCallInput memory input = SendAndCallInput({
            destinationBlockchainID: CCHAIN_BLOCKCHAIN_ID,
            destinationTokenTransferrerAddress: USDC_TOKEN_HOME,
            recipientContract: LENDER_CONTRACT,
            fallbackRecipient: vm.addr(deployerPrivateKey),
            recipientPayload: abi.encode(instructions),
            requiredGasLimit: 3_500_000,
            recipientGasLimit: 3_150_000,
            primaryFeeTokenAddress: address(0),
            primaryFee: 0,
            secondaryFee: 0,
            multiHopFallback: address(0)
        });

        vm.createSelectFork(vm.envString("CCHAIN_RPC_URL"));
        address positionHolder = ICrossChainLender(LENDER_CONTRACT).positionHolders(vm.addr(deployerPrivateKey));
        uint256 debt = IERC20(USDC_VARIABLE_DEBT_TOKEN).balanceOf(positionHolder) + 1e5;

        vm.selectFork(forkIdCoq);

        vm.startBroadcast(deployerPrivateKey);
        IERC20(USDC_TOKEN_REMOTE).approve(USDC_TOKEN_REMOTE, debt);
        IERC20TokenTransferrer(USDC_TOKEN_REMOTE).sendAndCall(input, debt);

        vm.stopBroadcast();
    }
}

// forge script --rpc-url $COQ_RPC_URL script/RepayUsdcWithdrawAvax.s.sol:RepayUsdcWithdrawAvax --skip-simulation --broadcast

contract WarpMessengerMock {
    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID) {}
}
