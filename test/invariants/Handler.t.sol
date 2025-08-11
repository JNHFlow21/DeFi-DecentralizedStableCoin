// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockToken} from "../../src/mocks/mock_WETH_WBTC.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    MockToken public weth;
    MockToken public wbtc;
    MockV3Aggregator public ethFeed;
    MockV3Aggregator public btcFeed;

    uint96 constant MAX_DEPOSIT = type(uint96).max; // 省gas，且96的max已经够用了

    /**
     * @notice 初始化 Handler，注入引擎、稳定币与两种抵押品及其价格源
     * @param _engine DSCEngine 合约
     * @param _dsc 稳定币合约
     * @param weth_ WETH 地址
     * @param wbtc_ WBTC 地址
     * @param ethFeed_ WETH/USD 价格源
     * @param btcFeed_ WBTC/USD 价格源
     */
    constructor(
        DSCEngine _engine,
        DecentralizedStableCoin _dsc,
        address weth_,
        address wbtc_,
        address ethFeed_,
        address btcFeed_
    ) {
        engine = _engine;
        dsc = _dsc;
        weth = MockToken(weth_);
        wbtc = MockToken(wbtc_);
        ethFeed = MockV3Aggregator(ethFeed_);
        btcFeed = MockV3Aggregator(btcFeed_);
    }

    // ==== Actions（Fuzzer 会随机挑一部分顺序执行）====

    /**
     * @notice 铸造并抵押随机一种抵押物
     * @param seed 选择 WETH/WBTC 的种子
     * @param amount 铸造并抵押的数量
     */
    function mintAndDepositCollateral(uint256 seed, uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT);
        MockToken col = _pick(seed);
        // 给调用者铸造，授权，入金
        col.mint(msg.sender, amount);
        vm.startPrank(msg.sender);
        col.approve(address(engine), amount);
        engine.depositCollateral(address(col), amount);
        vm.stopPrank();
    }

    /**
     * @notice 在抵押额度内铸造 DSC
     * @param amount 期望铸造数量（将按额度约束）
     */
    function mintDsc(uint256 amount) public {
        // 当前抵押总美元价值
        uint256 colUsd = engine.getAccountCollateralValue(msg.sender);

        // 允许借到的上限（例：阈值50% => 需要200%抵押）
        uint256 th = engine.getLiquidationThreshold(); // 50
        uint256 den = engine.getLiquidationPrecision(); // 100
        uint256 maxBorrow = (colUsd * th) / den;

        uint256 already = engine.getDscMinted(msg.sender);
        if (maxBorrow <= already) return; // 没额度就不借

        uint256 room = maxBorrow - already;
        amount = bound(amount, 1, room); // 关键：按额度约束

        vm.prank(msg.sender);
        try engine.mintDsc(amount) {} catch { /* 允许在 ContinueOnRevert 套件里继续 */ }
    }

    /**
     * @notice 烧毁调用者持有的 DSC，最多烧到当前余额
     * @param amount 期望销毁数量
     */
    function burnDsc(uint256 amount) public {
        amount = bound(amount, 0, dsc.balanceOf(msg.sender));
        if (amount == 0) return;
        vm.startPrank(msg.sender);
        dsc.approve(address(engine), amount);
        try engine.burnDsc(amount) {} catch {}
        vm.stopPrank();
    }

    /**
     * @notice 赎回调用者的部分抵押物
     * @param seed 选择 WETH/WBTC 的种子
     * @param amount 期望赎回数量（将按余额约束）
     */
    function redeemCollateral(uint256 seed, uint256 amount) public {
        MockToken col = _pick(seed);
        uint256 maxAmt = engine.getCollateralBalanceOfUser(msg.sender, address(col));
        amount = bound(amount, 0, maxAmt);
        if (amount == 0) return;

        vm.prank(msg.sender);
        try engine.redeemCollateral(address(col), amount) {} catch {}
    }

    /**
     * @notice 清算目标用户的部分债务
     * @param seed 选择 WETH/WBTC 的种子
     * @param user 被清算用户
     * @param debtToCover 覆盖的 DSC 债务
     */
    function liquidate(uint256 seed, address user, uint256 debtToCover) public {
        MockToken col = _pick(seed);
        debtToCover = bound(debtToCover, 1e18, uint256(MAX_DEPOSIT));

        // 给清算者准备 DSC，并授权
        deal(address(dsc), msg.sender, debtToCover);
        vm.prank(msg.sender);
        dsc.approve(address(engine), debtToCover);

        try engine.liquidate(address(col), user, debtToCover) {} catch {}
    }

    // 价格更新（同精度 1e8）
    /**
     * @notice 更新 ETH/USD 喂价（受上下限约束）
     * @param p 新价格（同精度 1e8）
     */
    function updateEthPrice(uint96 p) public {
        uint8 dec = ethFeed.decimals(); // 通常 8
        uint256 min = 500 * 10 ** dec; // $500
        uint256 max = 5000 * 10 ** dec; // $5000
        uint256 bounded = bound(uint256(p), min, max);
        ethFeed.updateAnswer(int256(bounded));
    }

    /**
     * @notice 更新 BTC/USD 喂价（受上下限约束）
     * @param p 新价格（同精度 1e8）
     */
    function updateBtcPrice(uint96 p) public {
        uint8 dec = btcFeed.decimals();
        uint256 min = 10_000 * 10 ** dec; // 例如 $10k
        uint256 max = 100_000 * 10 ** dec; // 例如 $100k
        uint256 bounded = bound(uint256(p), min, max);
        btcFeed.updateAnswer(int256(bounded));
    }

    // ==== helpers ====
    /**
     * @notice 根据种子在 WETH/WBTC 中二选一
     * @param seed 输入种子
     * @return 选中的 MockToken
     */
    function _pick(uint256 seed) internal view returns (MockToken) {
        return (seed % 2 == 0) ? weth : wbtc;
    }
}
