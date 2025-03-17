// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/AaveLender.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {BaseLendingInstructions, LendingAction} from "../src/interfaces/ICrossChainLender.sol";
import {AaveLendingInstructions} from "../src/interfaces/IAaveLender.sol";
import {MockTokenTransferrer} from "./mocks/MockTokenTransferrer.sol";

contract AaveLenderTest is Test {
    address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant WRAPPED_NATIVE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    bytes32 public constant DESTINATION_BLOCKCHAIN_ID =
        0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33;

    address constant ALICE = address(0x1);
    uint256 constant AVAX_AMOUNT = 100 ether;

    AaveLender lender;

    function setUp() public {
        lender = new AaveLender(WRAPPED_NATIVE);

        vm.label(ALICE, "Alice");
        vm.label(address(lender), "AaveLender");
    }

    function createLendingInstructions(address sourceTokenTransferrer, uint8 riskFactor, LendingAction action)
        internal
        pure
        returns (BaseLendingInstructions memory)
    {
        AaveLendingInstructions memory aaveInstructions = AaveLendingInstructions({
            poolAddress: AAVE_POOL,
            collateralAsset: WRAPPED_NATIVE,
            borrowAsset: USDC,
            referralCode: 0
        });

        return BaseLendingInstructions({
            sourceTokenTransferrerAddress: sourceTokenTransferrer,
            destinationTokenTransferrerAddress: sourceTokenTransferrer,
            destinationBlockchainID: DESTINATION_BLOCKCHAIN_ID,
            riskFactor: riskFactor,
            protocolData: abi.encode(aaveInstructions),
            action: action
        });
    }

    function createLendingInstructions(address sourceTokenTransferrer, uint8 riskFactor)
        internal
        pure
        returns (BaseLendingInstructions memory)
    {
        return createLendingInstructions(sourceTokenTransferrer, riskFactor, LendingAction.Borrow);
    }

    function test_BorrowAndRepay() public {
        uint256 collateralAmount = AVAX_AMOUNT;

        MockTokenTransferrer borrowTokenTransferrer = new MockTokenTransferrer(USDC);
        BaseLendingInstructions memory borrowInstructions =
            createLendingInstructions(address(borrowTokenTransferrer), 50, LendingAction.Borrow);

        bytes memory borrowPayload = abi.encode(borrowInstructions);

        deal(WRAPPED_NATIVE, address(this), collateralAmount);
        IERC20(WRAPPED_NATIVE).approve(address(lender), collateralAmount);

        lender.receiveTokens(bytes32(0), address(0), ALICE, WRAPPED_NATIVE, collateralAmount, borrowPayload);

        address positionHolder = lender.positionHolders(ALICE);
        assertTrue(positionHolder != address(0), "Position holder not created");

        assertTrue(borrowTokenTransferrer.sendCalled(), "Token transferrer not called for borrow");
        uint256 borrowedAmount = borrowTokenTransferrer.lastAmount();
        assertTrue(borrowedAmount > 0, "No tokens borrowed");

        MockTokenTransferrer repayTokenTransferrer = new MockTokenTransferrer(WRAPPED_NATIVE);
        BaseLendingInstructions memory repayInstructions =
            createLendingInstructions(address(repayTokenTransferrer), 50, LendingAction.Repay);

        bytes memory repayPayload = abi.encode(repayInstructions);

        deal(USDC, address(this), borrowedAmount);
        IERC20(USDC).approve(address(lender), borrowedAmount);

        lender.receiveTokens(bytes32(0), address(0), ALICE, USDC, borrowedAmount, repayPayload);

        assertTrue(repayTokenTransferrer.sendCalled(), "Token transferrer not called for repay");
        assertEq(
            repayTokenTransferrer.lastDestinationBlockchainID(),
            DESTINATION_BLOCKCHAIN_ID,
            "Wrong destination blockchain ID"
        );
        assertEq(repayTokenTransferrer.lastRecipient(), ALICE, "Wrong recipient");

        assertTrue(repayTokenTransferrer.lastAmount() > 0, "No collateral withdrawn");

        console.log("Borrowed USDC:", borrowedAmount);
        console.log("Withdrawn AVAX:", repayTokenTransferrer.lastAmount());
    }

    function test_ReceiveNative() public {
        uint256 nativeAmount = 1 ether;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);

        BaseLendingInstructions memory instructions = createLendingInstructions(address(mockTokenTransferrer), 50);

        bytes memory payload = abi.encode(instructions);

        lender.receiveTokens{value: nativeAmount}(bytes32(0), address(0), ALICE, payload);

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

    function test_RiskFactor_Minimum() public {
        testRiskFactor(1);
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
        uint256 collateralAmount = AVAX_AMOUNT;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);

        BaseLendingInstructions memory instructions =
            createLendingInstructions(address(mockTokenTransferrer), riskFactor);

        bytes memory payload = abi.encode(instructions);

        deal(WRAPPED_NATIVE, address(this), collateralAmount);
        IERC20(WRAPPED_NATIVE).approve(address(lender), collateralAmount);

        lender.receiveTokens(bytes32(0), address(0), ALICE, WRAPPED_NATIVE, collateralAmount, payload);

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

    function test_InvalidRiskFactorZero() public {
        uint256 collateralAmount = AVAX_AMOUNT;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);

        BaseLendingInstructions memory instructions = createLendingInstructions(address(mockTokenTransferrer), 0);

        bytes memory payload = abi.encode(instructions);

        deal(WRAPPED_NATIVE, address(this), collateralAmount);
        IERC20(WRAPPED_NATIVE).approve(address(lender), collateralAmount);

        vm.expectRevert("Risk factor must be between 1-100");

        lender.receiveTokens(bytes32(0), address(0), ALICE, WRAPPED_NATIVE, collateralAmount, payload);
    }

    function test_InvalidRiskFactorTooHigh() public {
        uint256 collateralAmount = AVAX_AMOUNT;

        MockTokenTransferrer mockTokenTransferrer = new MockTokenTransferrer(USDC);

        BaseLendingInstructions memory instructions = createLendingInstructions(address(mockTokenTransferrer), 101);

        bytes memory payload = abi.encode(instructions);

        deal(WRAPPED_NATIVE, address(this), collateralAmount);
        IERC20(WRAPPED_NATIVE).approve(address(lender), collateralAmount);

        vm.expectRevert("Risk factor must be between 1-100");

        lender.receiveTokens(bytes32(0), address(0), ALICE, WRAPPED_NATIVE, collateralAmount, payload);
    }
}
