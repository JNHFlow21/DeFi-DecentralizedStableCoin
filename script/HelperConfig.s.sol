// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockToken} from "../src/mocks/mock_WETH_WBTC.sol";

struct ChainConfig {
    // Deployer
    uint256 deployerPrivateKey;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
}

contract HelperConfig is Script {
    // Active Chain Config
    ChainConfig public activeChainConfig;

    // Environment Variables
    // RPC_URL
    string constant SEPOLIA_RPC_URL = "SEPOLIA_RPC_URL";
    string constant MAINNET_RPC_URL = "MAINNET_RPC_URL";
    string constant ANVIL_RPC_URL = "ANVIL_RPC_URL";
    // Private Key
    string constant SEPOLIA_PRIVATE_KEY = "SEPOLIA_PRIVATE_KEY";
    string constant MAINNET_PRIVATE_KEY = "MAINNET_PRIVATE_KEY";
    string constant ANVIL_PRIVATE_KEY = "ANVIL_PRIVATE_KEY";
    // Price Feed Variables
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_ETH_PRICE = 3000e8;
    int256 public constant INITIAL_BTC_PRICE = 11000e8; 

    constructor() {
        uint256 chainId = block.chainid;
        if (chainId == 31337 || chainId == 1337) {
            activeChainConfig = getOrCreateAnvilConfig();
        } else if (chainId == 11155111) {
            activeChainConfig = getSepoliaConfig();
        } else if (chainId == 1) {
            activeChainConfig = getMainnetConfig();
        } else {
            revert("Chain not supported");
        }
    }

    // 要想在部署脚本中可见，必须使用external
    function getActiveChainConfig() external view returns (ChainConfig memory) {
        return activeChainConfig;
    }

    function getOrCreateAnvilConfig() public returns (ChainConfig memory AnvilConfig) {

        vm.startBroadcast();

        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ETH_PRICE);
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_BTC_PRICE);

        // erc20 token
        MockToken weth = new MockToken("WETH", "WETH");
        MockToken wbtc = new MockToken("WBTC", "WBTC");

        vm.stopBroadcast();

        AnvilConfig = ChainConfig({
            deployerPrivateKey: vm.envUint(ANVIL_PRIVATE_KEY),
            wethUsdPriceFeed: address(wethPriceFeed),
            wbtcUsdPriceFeed: address(wbtcPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc)
        });
        return AnvilConfig;
    }

    function getSepoliaConfig() public view returns (ChainConfig memory SepoliaConfig) {
        SepoliaConfig = ChainConfig({
            deployerPrivateKey: vm.envUint(SEPOLIA_PRIVATE_KEY),
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,   // https://sepolia.ethplorer.io/address/0xfff9976782d46cc05630d1f6ebab18b2324d6b14?utm_source=chatgpt.com#
            wbtc: 0x29f2D40B0605204364af54EC677bD022dA425d03    // https://sepolia.ethplorer.io/address/0x29f2d40b0605204364af54ec677bd022da425d03?utm_source=chatgpt.com#
        });
        return SepoliaConfig;
    }

    function getMainnetConfig() public pure returns (ChainConfig memory MainnetConfig) {
        return MainnetConfig;
    }
}
