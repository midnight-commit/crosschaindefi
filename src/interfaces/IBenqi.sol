// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IQiToken {
    function mint(uint256 mintAmount) external returns (uint256);
    function mint() external payable;
    function borrow(uint256 borrowAmount) external returns (uint256);
    function underlying() external view returns (address);
    function exchangeRateStored() external view returns (uint256);
    function comptroller() external view returns (address);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
}

interface IComptroller {
    function enterMarkets(address[] memory qiTokens) external returns (uint256[] memory);
    function getHypotheticalAccountLiquidity(
        address account,
        address qiTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256, uint256);
    function oracle() external view returns (IPriceOracle);
}

interface IPriceOracle {
    function getUnderlyingPrice(address qiToken) external view returns (uint256);
}
