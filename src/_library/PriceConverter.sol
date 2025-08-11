// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceConverter
 * @dev ETH/USD价格转换库，使用Chainlink价格预言机
 */
library PriceConverter {
    /**
     * @notice 获取 ETH/USD 最新价格
     * @dev 返回值为 8 位精度（与 Chainlink Aggregator 对齐）
     * @param priceFeed 价格预言机地址
     * @return 价格，8 位精度
     */
    function getPrice(address priceFeed) internal view returns (uint256) {
        AggregatorV3Interface ethUsdPriceFeed = AggregatorV3Interface(priceFeed);
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        return uint256(price);
    }

    /**
     * @notice 获取 ETH 价值对应的 USD 金额
     * @dev 将 Aggregator 的 8 位结果转换到 18 位精度
     * @param ethAmount ETH 数量，18 位精度
     * @param priceFeed 价格预言机地址
     * @return 等值 USD 金额，18 位精度
     */
    function getUsdValue(uint256 ethAmount, address priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        // ETH价格有8位精度，转换为18位精度
        uint256 ethPriceInWei = ethPrice * 1e10;
        uint256 ethToUsd = (ethPriceInWei * ethAmount) / 1e18;
        return ethToUsd;
    }

    /**
     * @notice 根据 USD 金额计算等值的 ETH 数量
     * @dev 反向计算，维持 18 位内部精度
     * @param usdAmount USD 金额，18 位精度
     * @param priceFeed 价格预言机地址
     * @return 等值 ETH 数量，18 位精度
     */
    function getTokenAmount(uint256 usdAmount, address priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        // ETH价格有8位精度，转换为18位精度
        uint256 ethPriceInWei = ethPrice * 1e10;
        uint256 usdToEth = (usdAmount * 1e18) / ethPriceInWei;
        return usdToEth;
    }
}
