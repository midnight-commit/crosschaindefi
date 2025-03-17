// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {IERC20TokenTransferrer} from "../lib/icm-contracts/contracts/ictt/interfaces/IERC20TokenTransferrer.sol";
import {SendAndCallInput} from "../lib/icm-contracts/contracts/ictt/interfaces/ITokenTransferrer.sol";
import {BaseLendingInstructions, LendingAction, ICrossChainLender} from "../src/interfaces/ICrossChainLender.sol";
import {BenqiLendingInstructions} from "../src/interfaces/IBenqiLender.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IQiToken} from "../src/interfaces/IBenqi.sol";

contract RepayUsdcWithdrawAvaxBenqi is Script {
    bytes32 constant CCHAIN_BLOCKCHAIN_ID = 0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652;
    bytes32 constant COQ_BLOCKCHAIN_ID = 0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33;
    address constant LENDER_CONTRACT = 0xf055e2D801c05C63d0dF4106589ec212B8B67e37;
    address constant WAVAX_TOKEN_HOME = 0x30CdA6AF61c3A07ca81909699C85307DEF4398E5;
    address constant WAVAX_TOKEN_REMOTE = 0x28aF629a9F3ECE3c8D9F0b7cCf6349708CeC8cFb;
    address constant USDC_TOKEN_HOME = 0x97bBA61F61f2b0eEF60428947b990457f8eCb3a3;
    address constant USDC_TOKEN_REMOTE = 0x00396774d1E5b1C2B175B0F0562f921887678771;

    address constant QI_AVAX = 0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c;
    address constant QI_USDC = 0xB715808a78F6041E46d61Cb123C9B4A27056AE9C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TESTER_PRIVATE_KEY");
        WarpMessengerMock warp = new WarpMessengerMock();
        vm.etch(0x0200000000000000000000000000000000000005, address(warp).code);
        uint256 forkIdCoq = vm.activeFork();

        BenqiLendingInstructions memory benqiInstructions =
            BenqiLendingInstructions({collateralQiToken: QI_AVAX, borrowQiToken: QI_USDC});

        BaseLendingInstructions memory instructions = BaseLendingInstructions({
            sourceTokenTransferrerAddress: WAVAX_TOKEN_HOME,
            destinationTokenTransferrerAddress: WAVAX_TOKEN_REMOTE,
            destinationBlockchainID: COQ_BLOCKCHAIN_ID,
            riskFactor: 0,
            protocolData: abi.encode(benqiInstructions),
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
        uint256 debt = IQiToken(QI_USDC).borrowBalanceCurrent(positionHolder) + 1e5;

        vm.selectFork(forkIdCoq);
        vm.startBroadcast(deployerPrivateKey);

        IERC20(USDC_TOKEN_REMOTE).approve(USDC_TOKEN_REMOTE, debt);
        IERC20TokenTransferrer(USDC_TOKEN_REMOTE).sendAndCall(input, debt);

        vm.stopBroadcast();
    }
}

// forge script --rpc-url $COQ_RPC_URL script/RepayUsdcWithdrawAvaxBenqi.s.sol:RepayUsdcWithdrawAvaxBenqi --skip-simulation --broadcast
contract WarpMessengerMock {
    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID) {}
}
