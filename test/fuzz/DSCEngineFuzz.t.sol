// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockToken} from "../../src/mocks/mock_WETH_WBTC.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {ChainConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * 无状态测试（stateless fuzz test）：
 * - 不依赖合约的历史状态，仅依赖本次调用的输入参数和输出结果
 * - 只测试单个函数的逻辑，不会在多次调用间保留状态（memoryless）
 * - 重点在于通过随机化/约束输入范围，验证函数在各种可能输入下的正确性
 */
contract DSCEngineFuzz is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    ChainConfig cfg;
    MockToken weth;
    MockToken wbtc;
    MockV3Aggregator ethFeed;
    MockV3Aggregator btcFeed;

    address alice = makeAddr("alice");

    // 你的精度约定
    uint256 constant TOKEN_1 = 1e18; // 抵押物精度
    uint256 constant USD_1 = 1e18; // USD 内部使用 1e18
    uint256 constant PRICE_1 = 1e8; // 预言机价格精度

    /**
     * @notice 部署并初始化依赖：引擎、稳定币、喂价与 Mock 抵押物；设置 alice 的初始资产与授权
     */
    function setUp() public {
        DeployDSCEngine d = new DeployDSCEngine();
        (dsc, engine, cfg) = d.run();

        weth = MockToken(cfg.weth);
        wbtc = MockToken(cfg.wbtc);
        ethFeed = MockV3Aggregator(cfg.wethUsdPriceFeed);
        btcFeed = MockV3Aggregator(cfg.wbtcUsdPriceFeed);

        // 给 alice 初始资产
        weth.mint(alice, 1_000 * TOKEN_1);
        wbtc.mint(alice, 1_000 * TOKEN_1);
        vm.prank(alice);
        dsc.approve(address(engine), type(uint256).max);
    }

    /**
     * @notice 内部辅助：对用户进行抵押
     * @param user 用户地址
     * @param token 抵押物地址
     * @param amount 抵押数量
     */
    function _deposit(address user, address token, uint256 amount) internal {
        vm.startPrank(user);
        MockToken(token).approve(address(engine), amount);
        engine.depositCollateral(token, amount);
        vm.stopPrank();
    }

    /// depositCollateral: amount > 0 && 授权充分 => 成功并记账
    /**
     * @notice depositCollateral: amount > 0 且已授权 -> 成功并记账
     * @param amt 随机金额，将被映射到合适的范围
     */
    function testFuzz_depositCollateral_ok(uint256 amt) public {
        amt = bound(amt, 1, 100 * TOKEN_1); // 直接把传入的随机值 x 映射到你想要的区间，超出范围就压缩到范围内
        _deposit(alice, cfg.weth, amt);
        assertEq(engine.getCollateralBalanceOfUser(alice, cfg.weth), amt);
        assertEq(weth.balanceOf(address(engine)), amt);
    }

    /// depositCollateral: amount == 0 -> revert
    /**
     * @notice depositCollateral: amount == 0 -> revert
     * @param maybeZero 通过 assume 使之为 0
     */
    function testFuzz_depositCollateral_zero_reverts(uint256 maybeZero) public {
        vm.assume(maybeZero == 0); // 假设条件成立，不成立就直接跳过这一轮 fuzz case
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(cfg.weth, maybeZero);
    }

    /// mintDsc: 在抵押足够后，任意铸造量（不超过 HF 限制）都应该成功
    /**
     * @notice 在抵押足够后，任意铸造量（不超过 HF 限制）都应该成功
     * @param mintAmt 任意铸造量（将被约束到合法范围）
     */
    function testFuzz_mintDsc_ok(uint256 mintAmt) public {
        // 先抵押 100 ETH
        _deposit(alice, cfg.weth, 100 * TOKEN_1);
        // 价格 3000 -> 抵押 USD = 100 * 3000 = 300_000 USD (1e18)
        // 阈值 50%，最大可借近似 150_000（忽略四舍五入）
        mintAmt = bound(mintAmt, 1, 150_000 * USD_1);
        vm.prank(alice);
        engine.mintDsc(mintAmt);
        assertEq(dsc.balanceOf(alice), mintAmt);
        assertEq(engine.getDscMinted(alice), mintAmt);
        assertGe(engine.getHealthFactor(alice), engine.getMinHealthFactor());
    }

    /// burnDsc: 任意已铸数量内的 burn 都应成功，HF 上升或保持
    /**
     * @notice burnDsc: 任意已铸数量内的 burn 都应成功，HF 上升或保持
     * @param burnAmt 任意销毁数量（将被约束到合法范围）
     */
    function testFuzz_burnDsc_ok(uint256 burnAmt) public {
        _deposit(alice, cfg.weth, 100 * TOKEN_1);
        vm.prank(alice);
        engine.mintDsc(100_000 * USD_1);
        burnAmt = bound(burnAmt, 1, 100_000 * USD_1);

        uint256 hfBefore = engine.getHealthFactor(alice);
        vm.prank(alice);
        engine.burnDsc(burnAmt);

        assertEq(engine.getDscMinted(alice), 100_000 * USD_1 - burnAmt);
        assertGe(engine.getHealthFactor(alice), hfBefore);
    }

    /// calculateHealthFactor: totalDscMinted == 0 -> max, dummy value -> 123
    /**
     * @notice calculateHealthFactor: totalDscMinted == 0 -> 返回最大值
     */
    function test_calculateHealthFactor_zeroDebt_returnsMax() public view {
        assertEq(engine.calculateHealthFactor(0, 123), type(uint256).max);
    }
}
