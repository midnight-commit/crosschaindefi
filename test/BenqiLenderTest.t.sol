// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/BenqiLender.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {BaseLendingInstructions, LendingAction} from "../src/interfaces/ICrossChainLender.sol";
import {BenqiLendingInstructions} from "../src/interfaces/IBenqiLender.sol";
import {MockTokenTransferrer} from "./mocks/MockTokenTransferrer.sol";

contract BenqiLenderTest is Test {
    address public constant COMPTROLLER_CORE_MARKET = 0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4;
    address public constant QITOKEN_AVAX_CORE_MARKET = 0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c;
    address public constant QITOKEN_USDC_CORE_MARKET = 0xB715808a78F6041E46d61Cb123C9B4A27056AE9C;
    address public constant COMPTROLLER = 0xD7c4006d33DA2A0A8525791ed212bbCD7Aca763F;
    address public constant QITOKEN_COQ = 0x0eBfebD41e1eA83Be5e911cDCd2730a0CCEE344d;
    address public constant QITOKEN_USDC = 0x6B35Eb18BCA06bD7d66a428eeb45aC7d200C1e4E;
    address public constant COQ = 0x420FcA0121DC28039145009570975747295f2329;
    address public constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public constant WRAPPED_NATIVE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    bytes32 public constant DESTINATION_BLOCKCHAIN_ID =
        0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33;

    address constant ALICE = address(0x1);
    uint256 constant AVAX_AMOUNT = 10 ether;
    uint256 constant COQ_AMOUNT = 100_000_000 ether;

    BenqiLender lender;

    function setUp() public {
        lender = new BenqiLender(WRAPPED_NATIVE);

        vm.label(ALICE, "Alice");
        vm.label(address(lender), "BenqiLender");
    }

    function createLendingInstructionsCoreMarket(address sourceTokenTransferrer, uint8 riskFactor)
        internal
        pure
        returns (BaseLendingInstructions memory)
    {
        BenqiLendingInstructions memory benqiInstructions = BenqiLendingInstructions({
            collateralQiToken: QITOKEN_AVAX_CORE_MARKET,
            borrowQiToken: QITOKEN_USDC_CORE_MARKET
        });

        return BaseLendingInstructions({
            sourceTokenTransferrerAddress: sourceTokenTransferrer,
            destinationTokenTransferrerAddress: sourceTokenTransferrer,
            destinationBlockchainID: DESTINATION_BLOCKCHAIN_ID,
            riskFactor: riskFactor,
            protocolData: abi.encode(benqiInstructions),
            action: LendingAction.Borrow
        });
    }

    function test_SupplyCollateralAndBorrow() public {
        uint256 collateralAmount = AVAX_AMOUNT;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);
        CrossChainLender(payable(lender)).allowlistCaller(address(this));

        BaseLendingInstructions memory instructions =
            createLendingInstructionsCoreMarket(address(mockTokenTransferrer), 50);

        bytes memory payload = abi.encode(instructions);

        deal(address(this), collateralAmount);

        lender.receiveTokens{value: collateralAmount}(bytes32(0), address(0), ALICE, payload);

        address positionHolder = lender.positionHolders(ALICE);
        assertTrue(positionHolder != address(0), "Position holder not created");

        assertTrue(mockTokenTransferrer.sendCalled(), "Token transferrer not called");
        assertEq(
            mockTokenTransferrer.lastDestinationBlockchainID(),
            DESTINATION_BLOCKCHAIN_ID,
            "Wrong destination blockchain ID"
        );
        assertEq(mockTokenTransferrer.lastRecipient(), ALICE, "Wrong recipient");
        assertTrue(mockTokenTransferrer.lastAmount() > 0, "No tokens sent");
    }

    function createLendingInstructions(address sourceTokenTransferrer, uint8 riskFactor)
        internal
        pure
        returns (BaseLendingInstructions memory)
    {
        BenqiLendingInstructions memory benqiInstructions =
            BenqiLendingInstructions({collateralQiToken: QITOKEN_COQ, borrowQiToken: QITOKEN_USDC});

        return BaseLendingInstructions({
            sourceTokenTransferrerAddress: sourceTokenTransferrer,
            destinationTokenTransferrerAddress: sourceTokenTransferrer,
            destinationBlockchainID: DESTINATION_BLOCKCHAIN_ID,
            riskFactor: riskFactor,
            protocolData: abi.encode(benqiInstructions),
            action: LendingAction.Borrow
        });
    }

    function test_RiskFactor_Low() public {
        testRiskFactor(25);
    }

    function test_RiskFactor_Medium() public {
        testRiskFactor(50);
    }

    function test_RiskFactor_High() public {
        testRiskFactor(75);
    }

    function test_RiskFactor_Maximum() public {
        testRiskFactor(100);
    }

    function testRiskFactor(uint8 riskFactor) internal {
        uint256 collateralAmount = COQ_AMOUNT;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);
        CrossChainLender(payable(lender)).allowlistCaller(address(this));

        BaseLendingInstructions memory instructions =
            createLendingInstructions(address(mockTokenTransferrer), riskFactor);

        bytes memory payload = abi.encode(instructions);

        deal(COQ, address(this), collateralAmount);
        IERC20(COQ).approve(address(lender), collateralAmount);

        lender.receiveTokens(bytes32(0), address(0), ALICE, COQ, collateralAmount, payload);

        address positionHolder = lender.positionHolders(ALICE);
        assertTrue(positionHolder != address(0), "Position holder not created");

        assertTrue(mockTokenTransferrer.sendCalled(), "Token transferrer not called");
        assertEq(
            mockTokenTransferrer.lastDestinationBlockchainID(),
            DESTINATION_BLOCKCHAIN_ID,
            "Wrong destination blockchain ID"
        );
        assertEq(mockTokenTransferrer.lastRecipient(), ALICE, "Wrong recipient");
        assertTrue(mockTokenTransferrer.lastAmount() > 0, "No tokens sent");

        console.log("Risk factor:", riskFactor, "Amount:", mockTokenTransferrer.lastAmount());
    }

    function testManualRepay() public {
        uint256 collateralAmount = AVAX_AMOUNT;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);
        CrossChainLender(payable(lender)).allowlistCaller(address(this));

        BaseLendingInstructions memory instructions =
            createLendingInstructionsCoreMarket(address(mockTokenTransferrer), 50);

        bytes memory payload = abi.encode(instructions);

        deal(address(this), collateralAmount);

        lender.receiveTokens{value: collateralAmount}(bytes32(0), address(0), address(this), payload);

        address positionHolder = lender.positionHolders(address(this));
        assertTrue(positionHolder != address(0), "Position holder not created");

        BenqiLendingInstructions memory benqiInstructions = BenqiLendingInstructions({
            collateralQiToken: QITOKEN_AVAX_CORE_MARKET,
            borrowQiToken: QITOKEN_USDC_CORE_MARKET
        });
        deal(USDC, address(this), 5000e6);
        IERC20(USDC).approve(address(lender), 5000e6);
        console.log("USDC: ", IERC20(USDC).balanceOf(address(this)));
        console.log("AVAX: ", address(this).balance);
        console.log("WAVAX: ", IERC20(WRAPPED_NATIVE).balanceOf(address(this)));
        lender.repay(USDC, 5000e6, benqiInstructions);
        console.log("USDC: ", IERC20(USDC).balanceOf(address(this)));
        console.log("AVAX: ", address(this).balance);
        console.log("WAVAX: ", IERC20(WRAPPED_NATIVE).balanceOf(address(this)));
        lender.withdraw(benqiInstructions);
        console.log("USDC: ", IERC20(USDC).balanceOf(address(this)));
        console.log("AVAX: ", address(this).balance);
        console.log("WAVAX: ", IERC20(WRAPPED_NATIVE).balanceOf(address(this)));
    }

    receive() external payable {}
}
