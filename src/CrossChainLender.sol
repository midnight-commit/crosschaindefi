// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {LendingInstructions} from "./interfaces/ICrossChainLender.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IComptroller, IQiToken, IPriceOracle} from "./interfaces/IBenqi.sol";
import {IERC20SendAndCallReceiver} from "@ictt/interfaces/IERC20SendAndCallReceiver.sol";
import {IERC20TokenTransferrer, SendTokensInput} from "@ictt/interfaces/IERC20TokenTransferrer.sol";

contract CrossChainLender is IERC20SendAndCallReceiver {
    IComptroller public immutable comptroller;

    constructor(address _comptroller) {
        comptroller = IComptroller(_comptroller);
    }

    function receiveTokens(
        bytes32,
        address,
        address originSenderAddress,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external override {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        LendingInstructions memory lendingInstructions = abi.decode(payload, (LendingInstructions));
        (uint256 collateralQiTokensMinted, address borrowedToken, uint256 borrowedAmount) = supplyCollateralAndBorrow(
            token, lendingInstructions.collateralQiToken, amount, lendingInstructions.borrowQiToken
        );
        IERC20(lendingInstructions.collateralQiToken).transfer(originSenderAddress, collateralQiTokensMinted);
        IERC20(borrowedToken).approve(lendingInstructions.sourceTokenTransferrerAddress, borrowedAmount);
        SendTokensInput memory sendTokensInput = SendTokensInput({
            destinationBlockchainID: lendingInstructions.destinationBlockchainID,
            destinationTokenTransferrerAddress: lendingInstructions.destinationTokenTransferrerAddress,
            recipient: originSenderAddress,
            primaryFeeTokenAddress: address(0),
            primaryFee: 0,
            secondaryFee: 0,
            requiredGasLimit: 350_000,
            multiHopFallback: address(0)
        });
        IERC20TokenTransferrer(lendingInstructions.sourceTokenTransferrerAddress).send(sendTokensInput, borrowedAmount);
    }

    function supplyCollateralAndBorrow(
        address tokenReceived,
        address collateralQiToken,
        uint256 collateralAmount,
        address borrowQiToken
    ) internal returns (uint256 collateralQiTokensMinted, address borrowedToken, uint256 borrowedAmount) {
        address underlyingCollateral = IQiToken(collateralQiToken).underlying();
        require(tokenReceived == underlyingCollateral, "Token mismatch");

        IERC20(underlyingCollateral).approve(collateralQiToken, collateralAmount);

        uint256 balanceBefore = IERC20(collateralQiToken).balanceOf(address(this));
        require(IQiToken(collateralQiToken).mint(collateralAmount) == 0, "Mint failed");
        collateralQiTokensMinted = IERC20(collateralQiToken).balanceOf(address(this)) - balanceBefore;

        address[] memory markets = new address[](1);
        markets[0] = collateralQiToken;
        uint256[] memory results = comptroller.enterMarkets(markets);
        require(results[0] == 0, "Enter market failed");

        (, uint256 safeMaxBorrow) = calculateMaxBorrow(collateralQiToken);

        borrowedToken = IQiToken(borrowQiToken).underlying();
        balanceBefore = IERC20(borrowedToken).balanceOf(address(this));
        require(IQiToken(borrowQiToken).borrow(safeMaxBorrow) == 0, "Borrow failed");
        borrowedAmount = IERC20(borrowedToken).balanceOf(address(this)) - balanceBefore;
    }

    function calculateMaxBorrow(address borrowQiToken)
        internal
        view
        returns (uint256 maxBorrow, uint256 safeMaxBorrow)
    {
        (uint256 err, uint256 liquidity, uint256 shortfall) =
            comptroller.getHypotheticalAccountLiquidity(address(this), borrowQiToken, 0, 0);
        require(err == 0, "Error calculating liquidity");
        require(liquidity > 0, "No liquidity available");

        uint256 borrowPrice = comptroller.oracle().getUnderlyingPrice(borrowQiToken);
        require(borrowPrice > 0, "Invalid borrow price");

        uint8 borrowDecimals = IERC20(IQiToken(borrowQiToken).underlying()).decimals();

        // liquidity is in 1e18
        // price is in 1e12
        // Output should be in borrowDecimals (e.g. 1e6 for USDC)
        maxBorrow = (liquidity * (10 ** borrowDecimals)) / (borrowPrice * 1e18);

        (err,, shortfall) = comptroller.getHypotheticalAccountLiquidity(address(this), borrowQiToken, 0, maxBorrow);
        require(err == 0, "Error calculating with borrow");
        require(shortfall == 0, "Borrow would cause shortfall");

        safeMaxBorrow = (maxBorrow * 50) / 100;
    }
}
