// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CrossChainLender} from "./CrossChainLender.sol";
import {BaseLendingInstructions} from "./interfaces/ICrossChainLender.sol";
import {BenqiLendingInstructions} from "./interfaces/IBenqiLender.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IComptroller, IQiToken, IPriceOracle} from "./interfaces/IBenqi.sol";
import {PositionHolder} from "./PositionHolder.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IWrappedNativeToken} from "@ictt/interfaces/IWrappedNativeToken.sol";

contract BenqiLender is CrossChainLender {
    using Address for address payable;

    constructor(address wrappedNative) CrossChainLender(wrappedNative) {}

    function _supplyCollateral(
        address positionHolder,
        address collateralToken,
        uint256 collateralAmount,
        bytes memory protocolData,
        uint256 nativeValue
    ) internal override {
        BenqiLendingInstructions memory instructions = abi.decode(protocolData, (BenqiLendingInstructions));
        address collateralQiToken = instructions.collateralQiToken;

        bytes memory encodedCalldata;
        bytes memory result;

        if (collateralToken != WRAPPED_NATIVE) {
            encodedCalldata = abi.encodeWithSelector(IERC20.approve.selector, collateralQiToken, collateralAmount);
            PositionHolder(payable(positionHolder)).manage(collateralToken, encodedCalldata, 0);
            PositionHolder(payable(positionHolder)).manage(
                collateralQiToken, abi.encodeWithSignature("mint(uint256)", collateralAmount), 0
            );
        } else {
            PositionHolder(payable(positionHolder)).manage(
                collateralQiToken, abi.encodeWithSignature("mint()"), nativeValue
            );
        }

        address comptroller = IQiToken(collateralQiToken).comptroller();
        address[] memory markets = new address[](1);
        markets[0] = collateralQiToken;
        encodedCalldata = abi.encodeWithSelector(IComptroller.enterMarkets.selector, markets);
        result = PositionHolder(payable(positionHolder)).manage(comptroller, encodedCalldata, 0);
        require(abi.decode(result, (uint256[]))[0] == 0, "Enter market failed");
    }

    function _calculateMaxBorrow(address positionHolder, bytes memory protocolData, uint8 riskFactor)
        internal
        view
        override
        returns (uint256 maxBorrow, uint256 safeMaxBorrow)
    {
        require(riskFactor > 0 && riskFactor <= 100, "Risk factor must be between 1-100");

        BenqiLendingInstructions memory instructions = abi.decode(protocolData, (BenqiLendingInstructions));
        address borrowQiToken = instructions.borrowQiToken;
        address comptroller = IQiToken(borrowQiToken).comptroller();

        uint256 err;
        uint256 liquidity;
        uint256 shortfall;
        (err, liquidity, shortfall) =
            IComptroller(comptroller).getHypotheticalAccountLiquidity(positionHolder, borrowQiToken, 0, 0);
        require(err == 0, "Error calculating liquidity");
        require(liquidity > 0, "No liquidity available");

        uint256 borrowPrice = IComptroller(comptroller).oracle().getUnderlyingPrice(borrowQiToken);
        require(borrowPrice > 0, "Invalid borrow price");

        address borrowToken = IQiToken(borrowQiToken).underlying();
        uint8 borrowDecimals = IERC20(borrowToken).decimals();
        maxBorrow = (liquidity * (10 ** borrowDecimals) * 1e12) / borrowPrice;

        (err, liquidity, shortfall) =
            IComptroller(comptroller).getHypotheticalAccountLiquidity(positionHolder, borrowQiToken, 0, maxBorrow);
        require(err == 0, "Error calculating with borrow");
        require(shortfall == 0, "Borrow would cause shortfall");

        safeMaxBorrow = (maxBorrow * riskFactor) / 100;
    }

    function _borrow(address positionHolder, bytes memory protocolData, uint256 borrowAmount)
        internal
        override
        returns (address borrowedToken, uint256 borrowedAmount)
    {
        BenqiLendingInstructions memory instructions = abi.decode(protocolData, (BenqiLendingInstructions));
        address borrowQiToken = instructions.borrowQiToken;

        bytes memory encodedCalldata;
        bytes memory result;

        borrowedToken = IQiToken(borrowQiToken).underlying();

        encodedCalldata = abi.encodeWithSelector(IQiToken.borrow.selector, borrowAmount);
        result = PositionHolder(payable(positionHolder)).manage(borrowQiToken, encodedCalldata, 0);
        require(abi.decode(result, (uint256)) == 0, "Borrow failed");

        borrowedAmount = IERC20(borrowedToken).balanceOf(positionHolder);
        encodedCalldata = abi.encodeWithSelector(IERC20.transfer.selector, address(this), borrowedAmount);
        PositionHolder(payable(positionHolder)).manage(borrowedToken, encodedCalldata, 0);

        return (borrowedToken, borrowedAmount);
    }

    function _repay(
        address positionHolder,
        address repayToken,
        uint256 repayAmount,
        bytes memory protocolData,
        uint256 nativeValue
    ) internal override {
        BenqiLendingInstructions memory instructions = abi.decode(protocolData, (BenqiLendingInstructions));
        address borrowQiToken = instructions.borrowQiToken;

        bytes memory encodedCalldata;
        bytes memory result;

        if (repayToken == WRAPPED_NATIVE && IQiToken(borrowQiToken).underlying() == WRAPPED_NATIVE) {
            PositionHolder(payable(positionHolder)).manage(
                borrowQiToken, abi.encodeWithSignature("repayBorrow(uint256)", type(uint256).max), nativeValue
            );
        } else {
            encodedCalldata = abi.encodeWithSelector(IERC20.approve.selector, borrowQiToken, repayAmount);
            PositionHolder(payable(positionHolder)).manage(repayToken, encodedCalldata, 0);

            encodedCalldata = abi.encodeWithSelector(IQiToken.repayBorrow.selector, type(uint256).max);
            result = PositionHolder(payable(positionHolder)).manage(borrowQiToken, encodedCalldata, 0);
            require(abi.decode(result, (uint256)) == 0, "Repay failed");
        }
    }

    function repay(address repayToken, uint256 repayAmount, BenqiLendingInstructions memory protocolData)
        public
        payable
    {
        address positionHolder = _getOrCreatePositionHolder(msg.sender);
        if (msg.value > 0) {
            payable(positionHolder).sendValue(msg.value);
            repayToken = WRAPPED_NATIVE;
            repayAmount = msg.value;
        } else {
            IERC20(repayToken).transferFrom(msg.sender, positionHolder, repayAmount);
        }
        bytes memory encodedInstructions = abi.encode(protocolData);
        _repay(positionHolder, repayToken, repayAmount, encodedInstructions, msg.value);
        bytes memory encodedCalldata =
            abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, IERC20(repayToken).balanceOf(positionHolder));
        PositionHolder(payable(positionHolder)).manage(repayToken, encodedCalldata, 0);
    }

    function _withdraw(address positionHolder, bytes memory protocolData)
        internal
        override
        returns (address withdrawnToken, uint256 withdrawnAmount)
    {
        BenqiLendingInstructions memory instructions = abi.decode(protocolData, (BenqiLendingInstructions));
        address collateralQiToken = instructions.collateralQiToken;

        bytes memory encodedCalldata;
        bytes memory result;

        bool isNativeToken = false;
        try IQiToken(collateralQiToken).underlying() returns (address) {
            isNativeToken = false;
        } catch {
            isNativeToken = true;
        }

        if (isNativeToken && collateralQiToken != address(0)) {
            withdrawnToken = WRAPPED_NATIVE;

            encodedCalldata = abi.encodeWithSelector(IQiToken.redeemUnderlying.selector, type(uint256).max);
            result = PositionHolder(payable(positionHolder)).manage(collateralQiToken, encodedCalldata, 0);
            require(abi.decode(result, (uint256)) == 0, "Redeem failed");

            uint256 nativeBalance = address(positionHolder).balance;

            encodedCalldata = abi.encodeWithSignature("deposit()");
            PositionHolder(payable(positionHolder)).manage(WRAPPED_NATIVE, encodedCalldata, nativeBalance);

            withdrawnAmount = IERC20(WRAPPED_NATIVE).balanceOf(positionHolder);
            encodedCalldata = abi.encodeWithSelector(IERC20.transfer.selector, address(this), withdrawnAmount);
            PositionHolder(payable(positionHolder)).manage(WRAPPED_NATIVE, encodedCalldata, 0);
        } else if (collateralQiToken != address(0)) {
            withdrawnToken = IQiToken(collateralQiToken).underlying();

            encodedCalldata = abi.encodeWithSelector(IQiToken.redeemUnderlying.selector, type(uint256).max);
            result = PositionHolder(payable(positionHolder)).manage(collateralQiToken, encodedCalldata, 0);
            require(abi.decode(result, (uint256)) == 0, "Redeem failed");

            withdrawnAmount = IERC20(withdrawnToken).balanceOf(positionHolder);
            encodedCalldata = abi.encodeWithSelector(IERC20.transfer.selector, address(this), withdrawnAmount);
            PositionHolder(payable(positionHolder)).manage(withdrawnToken, encodedCalldata, 0);
        }

        return (withdrawnToken, withdrawnAmount);
    }

    function withdraw(BenqiLendingInstructions memory protocolData)
        public
        returns (address withdrawnToken, uint256 withdrawnAmount)
    {
        address positionHolder = _getOrCreatePositionHolder(msg.sender);
        bytes memory encodedInstructions = abi.encode(protocolData);
        (withdrawnToken, withdrawnAmount) = _withdraw(positionHolder, encodedInstructions);
        if (withdrawnToken == WRAPPED_NATIVE) {
            IWrappedNativeToken(WRAPPED_NATIVE).withdraw(withdrawnAmount);
            payable(msg.sender).sendValue(withdrawnAmount);
        } else {
            IERC20(withdrawnToken).transfer(msg.sender, withdrawnAmount);
        }
    }
}
