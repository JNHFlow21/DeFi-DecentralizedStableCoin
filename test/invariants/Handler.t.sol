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

    function burnDsc(uint256 amount) public {
        amount = bound(amount, 0, dsc.balanceOf(msg.sender));
        if (amount == 0) return;
        vm.startPrank(msg.sender);
        dsc.approve(address(engine), amount);
        try engine.burnDsc(amount) {} catch {}
        vm.stopPrank();
    }

    function redeemCollateral(uint256 seed, uint256 amount) public {
        MockToken col = _pick(seed);
        uint256 maxAmt = engine.getCollateralBalanceOfUser(msg.sender, address(col));
        amount = bound(amount, 0, maxAmt);
        if (amount == 0) return;

        vm.prank(msg.sender);
        try engine.redeemCollateral(address(col), amount) {} catch {}
    }

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
    function updateEthPrice(uint96 p) public {
        uint8 dec = ethFeed.decimals(); // 通常 8
        uint256 min = 500 * 10 ** dec; // $500
        uint256 max = 5000 * 10 ** dec; // $5000
        uint256 bounded = bound(uint256(p), min, max);
        ethFeed.updateAnswer(int256(bounded));
    }

    function updateBtcPrice(uint96 p) public {
        uint8 dec = btcFeed.decimals();
        uint256 min = 10_000 * 10 ** dec; // 例如 $10k
        uint256 max = 100_000 * 10 ** dec; // 例如 $100k
        uint256 bounded = bound(uint256(p), min, max);
        btcFeed.updateAnswer(int256(bounded));
    }

    // ==== helpers ====
    function _pick(uint256 seed) internal view returns (MockToken) {
        return (seed % 2 == 0) ? weth : wbtc;
    }
}
