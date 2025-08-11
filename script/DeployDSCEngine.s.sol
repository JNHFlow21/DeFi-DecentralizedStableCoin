// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {HelperConfig, ChainConfig} from "./HelperConfig.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockToken} from "../src/mocks/mock_WETH_WBTC.sol";

contract DeployDSCEngine is Script {
    // Price Feed Variables
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_ETH_PRICE = 3000e8;
    int256 public constant INITIAL_BTC_PRICE = 11000e8;

    HelperConfig helperConfig = new HelperConfig();
    ChainConfig chainConfig = helperConfig.getActiveChainConfig();

    address[] private s_tokenAddresses;
    address[] private s_priceFeedAddresses;

    /**
     * @notice 部署 DSC 与 DSCEngine，并在本地缺省时部署 Mock 资产与价格源
     * @return dsc 已部署的稳定币实例
     * @return engine 已部署的引擎实例
     * @return cfg 使用的链配置（含资产与喂价地址）
     */
    function run() public returns (DecentralizedStableCoin, DSCEngine, ChainConfig memory) {
        vm.startBroadcast(chainConfig.deployerPrivateKey);
        // 部署 weth/wbtc 以及mockpricefeed
        if (chainConfig.weth == address(0) || chainConfig.wbtc == address(0) || chainConfig.wethUsdPriceFeed == address(0) || chainConfig.wbtcUsdPriceFeed == address(0)) {
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ETH_PRICE);
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_BTC_PRICE);

        // erc20 token
        MockToken weth = new MockToken("WETH", "WETH");
        MockToken wbtc = new MockToken("WBTC", "WBTC");

        chainConfig.weth = address(weth);
        chainConfig.wbtc = address(wbtc);
        chainConfig.wethUsdPriceFeed = address(wethPriceFeed);
        chainConfig.wbtcUsdPriceFeed = address(wbtcPriceFeed);
        }
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();

        initTokenAddressesAndPriceFeed();

        DSCEngine engine = new DSCEngine(s_tokenAddresses, s_priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();
        return (dsc, engine, chainConfig);
    }

    /**
     * @notice 初始化引擎构造所需的 token 与 price feed 地址数组
     */
    function initTokenAddressesAndPriceFeed() private {
        s_tokenAddresses = [chainConfig.weth, chainConfig.wbtc];
        s_priceFeedAddresses = [chainConfig.wethUsdPriceFeed, chainConfig.wbtcUsdPriceFeed];
    }
}
