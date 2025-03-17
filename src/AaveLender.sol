// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CrossChainLender} from "./CrossChainLender.sol";
import {BaseLendingInstructions} from "./interfaces/ICrossChainLender.sol";
import {AaveLendingInstructions} from "./interfaces/IAaveLender.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IPool, IPoolAddressesProvider, IPriceOracle, DataTypes, IProtocolDataProvider} from "./interfaces/IAave.sol";
import {PositionHolder} from "./PositionHolder.sol";

contract AaveLender is CrossChainLender {
    address public constant ADDRESSES_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;

    constructor(address wrappedNative) CrossChainLender(wrappedNative) {}

    function _supplyCollateral(
        address positionHolder,
        address collateralToken,
        uint256 collateralAmount,
        bytes memory protocolData,
        uint256 nativeValue
    ) internal override {
        AaveLendingInstructions memory instructions = abi.decode(protocolData, (AaveLendingInstructions));
        address poolAddress = instructions.poolAddress;
        address collateralAsset = instructions.collateralAsset;

        bytes memory encodedCalldata;

        if (collateralToken == WRAPPED_NATIVE) {
            encodedCalldata = abi.encodeWithSignature("deposit()");
            PositionHolder(payable(positionHolder)).manage(WRAPPED_NATIVE, encodedCalldata, nativeValue);

            collateralToken = WRAPPED_NATIVE;
            collateralAsset = WRAPPED_NATIVE;
        }

        encodedCalldata = abi.encodeWithSelector(IERC20.approve.selector, poolAddress, collateralAmount);
        PositionHolder(payable(positionHolder)).manage(collateralToken, encodedCalldata, 0);

        encodedCalldata = abi.encodeWithSelector(
            IPool.supply.selector, collateralAsset, collateralAmount, positionHolder, instructions.referralCode
        );
        PositionHolder(payable(positionHolder)).manage(poolAddress, encodedCalldata, 0);
    }

    function _calculateMaxBorrow(address positionHolder, bytes memory protocolData, uint8 riskFactor)
        internal
        view
        override
        returns (uint256 maxBorrow, uint256 safeMaxBorrow)
    {
        require(riskFactor > 0 && riskFactor <= 100, "Risk factor must be between 1-100");

        AaveLendingInstructions memory instructions = abi.decode(protocolData, (AaveLendingInstructions));

        IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(ADDRESSES_PROVIDER);

        (,, uint256 availableBorrowsBase,,, uint256 healthFactor) =
            IPool(instructions.poolAddress).getUserAccountData(positionHolder);

        require(availableBorrowsBase > 0, "No borrowing capacity available");
        require(healthFactor > 1e18, "Health factor too low");

        uint256 assetPrice = IPriceOracle(addressesProvider.getPriceOracle()).getAssetPrice(instructions.borrowAsset);
        require(assetPrice > 0, "Invalid asset price");

        uint8 assetDecimals = IERC20(instructions.borrowAsset).decimals();

        maxBorrow = (availableBorrowsBase * (10 ** assetDecimals)) / assetPrice;

        (,,,,,, uint256 availableLiquidity,,,,) =
            IProtocolDataProvider(addressesProvider.getPoolDataProvider()).getReserveData(instructions.borrowAsset);

        maxBorrow = maxBorrow < availableLiquidity ? maxBorrow : availableLiquidity;

        safeMaxBorrow = (maxBorrow * riskFactor) / 100;
    }

    function _borrow(address positionHolder, bytes memory protocolData, uint256 borrowAmount)
        internal
        override
        returns (address borrowedToken, uint256 borrowedAmount)
    {
        AaveLendingInstructions memory instructions = abi.decode(protocolData, (AaveLendingInstructions));
        address poolAddress = instructions.poolAddress;
        address borrowAsset = instructions.borrowAsset;

        bytes memory encodedCalldata;

        encodedCalldata = abi.encodeWithSelector(
            IPool.borrow.selector, borrowAsset, borrowAmount, 2, instructions.referralCode, positionHolder
        );
        PositionHolder(payable(positionHolder)).manage(poolAddress, encodedCalldata, 0);

        borrowedToken = borrowAsset;
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
        AaveLendingInstructions memory instructions = abi.decode(protocolData, (AaveLendingInstructions));

        bytes memory encodedCalldata;

        if (repayToken == WRAPPED_NATIVE && instructions.borrowAsset == WRAPPED_NATIVE) {
            encodedCalldata = abi.encodeWithSignature("deposit()");
            PositionHolder(payable(positionHolder)).manage(WRAPPED_NATIVE, encodedCalldata, nativeValue);
            repayToken = WRAPPED_NATIVE;
        }

        encodedCalldata = abi.encodeWithSelector(IERC20.approve.selector, instructions.poolAddress, repayAmount);
        PositionHolder(payable(positionHolder)).manage(repayToken, encodedCalldata, 0);

        encodedCalldata =
            abi.encodeWithSelector(IPool.repay.selector, instructions.borrowAsset, type(uint256).max, 2, positionHolder);
        PositionHolder(payable(positionHolder)).manage(instructions.poolAddress, encodedCalldata, 0);
    }

    function _withdraw(address positionHolder, bytes memory protocolData)
        internal
        override
        returns (address withdrawnToken, uint256 withdrawnAmount)
    {
        AaveLendingInstructions memory instructions = abi.decode(protocolData, (AaveLendingInstructions));

        bytes memory encodedCalldata = abi.encodeWithSelector(
            IPool.withdraw.selector, instructions.collateralAsset, type(uint256).max, address(this)
        );
        withdrawnAmount = abi.decode(
            PositionHolder(payable(positionHolder)).manage(instructions.poolAddress, encodedCalldata, 0), (uint256)
        );

        return (instructions.collateralAsset, withdrawnAmount);
    }
}
