// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceConverter
 * @dev ETH/USD价格转换库，使用Chainlink价格预言机
 */
library PriceConverter {
    /**
     * @dev 获取ETH/USD最新价格
     * @param priceFeed 价格预言机地址
     * @return 价格，8位精度
     */
    function getPrice(address priceFeed) internal view returns (uint256) {
        AggregatorV3Interface ethUsdPriceFeed = AggregatorV3Interface(priceFeed);
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        return uint256(price);
    }

    /**
     * @dev 获取ETH价值的USD金额
     * @param ethAmount ETH数量，18位精度
     * @param priceFeed 价格预言机地址
     * @return 等值USD金额，18位精度
     */
    function getUsdValue(uint256 ethAmount, address priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        // ETH价格有8位精度，转换为18位精度
        uint256 ethPriceInWei = ethPrice * 1e10;
        uint256 ethToUsd = (ethPriceInWei * ethAmount) / 1e18;
        return ethToUsd;
    }

    /**
     * @dev 根据USD金额计算等值ETH数量
     * @param usdAmount USD金额，18位精度
     * @param priceFeed 价格预言机地址
     * @return 等值ETH数量，18位精度
     */
    function getTokenAmount(uint256 usdAmount, address priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        // ETH价格有8位精度，转换为18位精度
        uint256 ethPriceInWei = ethPrice * 1e10;
        uint256 usdToEth = (usdAmount * 1e18) / ethPriceInWei;
        return usdToEth;
    }
}
