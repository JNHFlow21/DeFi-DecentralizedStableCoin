// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {HelperConfig, ChainConfig} from "./HelperConfig.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DeployDSCEngine is Script {
    HelperConfig helperConfig = new HelperConfig();
    ChainConfig chainConfig = helperConfig.getActiveChainConfig();

    address[] private s_tokenAddresses;
    address[] private s_priceFeedAddresses;

    function run() public returns (DecentralizedStableCoin, DSCEngine, ChainConfig memory) {
        vm.startBroadcast(chainConfig.deployerPrivateKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();

        initTokenAddressesAndPriceFeed();

        DSCEngine engine = new DSCEngine(s_tokenAddresses, s_priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();
        return (dsc, engine, chainConfig);
    }

    function initTokenAddressesAndPriceFeed() private {
        s_tokenAddresses = [chainConfig.weth, chainConfig.wbtc];
        s_priceFeedAddresses = [chainConfig.wethUsdPriceFeed, chainConfig.wbtcUsdPriceFeed];
    }
}
