// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceConverter
 * @dev ETH/USD价格转换库，使用Chainlink价格预言机
 */
library PriceConverter {
    error PriceConverter__InvalidPrice();
    error PriceConverter__StalePrice();

    /**
     * @notice 获取最新价格
     * @dev 返回值精度与 Aggregator 的 decimals 一致
     * @param priceFeed 价格预言机地址
     * @return 价格（Aggregator decimals）
     */
    function getPrice(address priceFeed) internal view returns (uint256) {
        AggregatorV3Interface ethUsdPriceFeed = AggregatorV3Interface(priceFeed);
        (uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) =
            ethUsdPriceFeed.latestRoundData();
        if (price <= 0) {
            revert PriceConverter__InvalidPrice();
        }
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert PriceConverter__StalePrice();
        }
        return uint256(price);
    }

    /**
     * @notice 获取 token 价值对应的 USD 金额
     * @dev 将 Aggregator 的 decimals 转换到 18 位内部精度
     * @param ethAmount token 数量，18 位精度
     * @param priceFeed 价格预言机地址
     * @return 等值 USD 金额，18 位精度
     */
    function getUsdValue(uint256 ethAmount, address priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        uint256 ethPriceInWei = _scalePrice(priceFeed, ethPrice);
        uint256 ethToUsd = (ethPriceInWei * ethAmount) / 1e18;
        return ethToUsd;
    }

    /**
     * @notice 根据 USD 金额计算等值的 token 数量
     * @dev 反向计算，维持 18 位内部精度
     * @param usdAmount USD 金额，18 位精度
     * @param priceFeed 价格预言机地址
     * @return 等值 token 数量，18 位精度
     */
    function getTokenAmount(uint256 usdAmount, address priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        uint256 ethPriceInWei = _scalePrice(priceFeed, ethPrice);
        uint256 usdToEth = (usdAmount * 1e18) / ethPriceInWei;
        return usdToEth;
    }

    function _scalePrice(address priceFeed, uint256 price) private view returns (uint256) {
        AggregatorV3Interface ethUsdPriceFeed = AggregatorV3Interface(priceFeed);
        uint256 decimals = uint256(ethUsdPriceFeed.decimals());
        if (decimals == 18) {
            return price;
        }
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        }
        return price / (10 ** (decimals - 18));
    }
}
