// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseLendingInstructions, LendingAction} from "./interfaces/ICrossChainLender.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC20SendAndCallReceiver} from "@ictt/interfaces/IERC20SendAndCallReceiver.sol";
import {INativeSendAndCallReceiver} from "@ictt/interfaces/INativeSendAndCallReceiver.sol";
import {IERC20TokenTransferrer, SendTokensInput} from "@ictt/interfaces/IERC20TokenTransferrer.sol";
import {INativeTokenTransferrer} from "@ictt/interfaces/INativeTokenTransferrer.sol";
import {IWrappedNativeToken} from "@ictt/interfaces/IWrappedNativeToken.sol";
import {PositionHolder} from "./PositionHolder.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract CrossChainLender is IERC20SendAndCallReceiver, INativeSendAndCallReceiver, Ownable {
    using Address for address payable;

    mapping(address => address) public positionHolders;
    mapping(address => bool) public allowlistedCallers;
    address public immutable WRAPPED_NATIVE;

    event CallerAllowlisted(address indexed caller);
    event CallerRemoved(address indexed caller);

    modifier onlyAllowlisted() {
        require(allowlistedCallers[msg.sender], "Caller not allowlisted");
        _;
    }

    constructor(address wrappedNative) Ownable(msg.sender) {
        WRAPPED_NATIVE = wrappedNative;
    }

    receive() external payable {}

    function allowlistCaller(address caller) external onlyOwner {
        allowlistedCallers[caller] = true;
        emit CallerAllowlisted(caller);
    }

    function removeCaller(address caller) external onlyOwner {
        allowlistedCallers[caller] = false;
        emit CallerRemoved(caller);
    }

    function receiveTokens(
        bytes32,
        address,
        address originSenderAddress,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external override onlyAllowlisted {
        address positionHolder = _getOrCreatePositionHolder(originSenderAddress);
        IERC20(token).transferFrom(msg.sender, positionHolder, amount);

        _receive(originSenderAddress, positionHolder, token, amount, payload, 0);
    }

    function receiveTokens(bytes32, address, address originSenderAddress, bytes calldata payload)
        external
        payable
        override
        onlyAllowlisted
    {
        address positionHolder = _getOrCreatePositionHolder(originSenderAddress);
        payable(positionHolder).sendValue(msg.value);
        _receive(originSenderAddress, positionHolder, WRAPPED_NATIVE, msg.value, payload, msg.value);
    }

    function _receive(
        address originSenderAddress,
        address positionHolder,
        address token,
        uint256 amount,
        bytes calldata payload,
        uint256 nativeValue
    ) internal {
        BaseLendingInstructions memory instructions = abi.decode(payload, (BaseLendingInstructions));

        address tokenOut;
        uint256 amountOut;

        if (instructions.action == LendingAction.Borrow) {
            _supplyCollateral(positionHolder, token, amount, instructions.protocolData, nativeValue);

            (, uint256 safeMaxBorrow) =
                _calculateMaxBorrow(positionHolder, instructions.protocolData, instructions.riskFactor);
            (tokenOut, amountOut) = _borrow(positionHolder, instructions.protocolData, safeMaxBorrow);
        } else if (instructions.action == LendingAction.Repay) {
            _repay(positionHolder, token, amount, instructions.protocolData, nativeValue);
            (tokenOut, amountOut) = _withdraw(positionHolder, instructions.protocolData);
        }

        uint256 remainingTokenBalance = IERC20(token).balanceOf(positionHolder);
        if (remainingTokenBalance > 0) {
            bytes memory encodedCalldata =
                abi.encodeWithSelector(IERC20.transfer.selector, originSenderAddress, remainingTokenBalance);
            PositionHolder(payable(positionHolder)).manage(token, encodedCalldata, 0);
        }

        if (amountOut > 0) {
            _sendTokens(originSenderAddress, tokenOut, amountOut, instructions);
        }
    }

    function _sendTokens(
        address originSenderAddress,
        address token,
        uint256 amount,
        BaseLendingInstructions memory instructions
    ) internal {
        SendTokensInput memory sendTokensInput = SendTokensInput({
            destinationBlockchainID: instructions.destinationBlockchainID,
            destinationTokenTransferrerAddress: instructions.destinationTokenTransferrerAddress,
            recipient: originSenderAddress,
            primaryFeeTokenAddress: address(0),
            primaryFee: 0,
            secondaryFee: 0,
            requiredGasLimit: 350_000,
            multiHopFallback: address(0)
        });

        if (token == WRAPPED_NATIVE) {
            IWrappedNativeToken(WRAPPED_NATIVE).withdraw(amount);
            INativeTokenTransferrer(instructions.sourceTokenTransferrerAddress).send{value: amount}(sendTokensInput);
        } else {
            IERC20(token).approve(instructions.sourceTokenTransferrerAddress, amount);
            IERC20TokenTransferrer(instructions.sourceTokenTransferrerAddress).send(sendTokensInput, amount);
        }
    }

    function _getOrCreatePositionHolder(address originSenderAddress) internal returns (address) {
        address positionHolder = positionHolders[originSenderAddress];

        if (positionHolder == address(0)) {
            PositionHolder newPositionHolder = new PositionHolder(originSenderAddress);
            positionHolder = address(newPositionHolder);
            positionHolders[originSenderAddress] = positionHolder;
        }

        return positionHolder;
    }

    function _supplyCollateral(
        address positionHolder,
        address collateralToken,
        uint256 collateralAmount,
        bytes memory protocolData,
        uint256 nativeValue
    ) internal virtual;

    function _calculateMaxBorrow(address positionHolder, bytes memory protocolData, uint8 riskFactor)
        internal
        view
        virtual
        returns (uint256 maxBorrow, uint256 safeMaxBorrow);

    function _borrow(address positionHolder, bytes memory protocolData, uint256 borrowAmount)
        internal
        virtual
        returns (address borrowedToken, uint256 borrowedAmount);

    function _repay(
        address positionHolder,
        address repayToken,
        uint256 repayAmount,
        bytes memory protocolData,
        uint256 nativeValue
    ) internal virtual;

    function _withdraw(address positionHolder, bytes memory protocolData)
        internal
        virtual
        returns (address withdrawnToken, uint256 withdrawnAmount);
}
