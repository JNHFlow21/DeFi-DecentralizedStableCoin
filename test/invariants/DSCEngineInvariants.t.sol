// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {ChainConfig} from "../../script/HelperConfig.s.sol";
import {MockToken} from "../../src/mocks/mock_WETH_WBTC.sol";
import {Handler} from "./Handler.t.sol";

contract DSCEngineInvariants is StdInvariant, Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    ChainConfig cfg;
    MockToken weth;
    MockToken wbtc;

    Handler handler;

    function setUp() external {
        DeployDSCEngine d = new DeployDSCEngine();
        (dsc, engine, cfg) = d.run();

        weth = MockToken(cfg.weth);
        wbtc = MockToken(cfg.wbtc);

        handler = new Handler(engine, dsc, cfg.weth, cfg.wbtc, cfg.wethUsdPriceFeed, cfg.wbtcUsdPriceFeed);

        // Fuzzer 会随机调用 handler 的函数
        targetContract(address(handler));
    }

    /// 不变量 1：协议资产价值 >= DSC 总供应（美元）
    function invariant_protocolSolvent() public view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 wethBal = weth.balanceOf(address(engine));
        uint256 wbtcBal = wbtc.balanceOf(address(engine));

        uint256 wethUsd = engine.getUsdValue(address(weth), wethBal);
        uint256 wbtcUsd = engine.getUsdValue(address(wbtc), wbtcBal);

        assertGe(wethUsd + wbtcUsd, totalSupply, "protocol insolvent");
    }

    /// 不变量 2：常用 getters 不应 revert
    function invariant_gettersNoRevert() public view {
        engine.getCollateralTokens();
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getLiquidationThreshold();
        engine.getMinHealthFactor();
        engine.getPrecision();
        engine.getDsc();
    }
}
