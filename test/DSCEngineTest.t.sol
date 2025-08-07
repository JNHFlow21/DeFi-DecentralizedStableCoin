// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {MockToken} from "../src/mocks/mock_WETH_WBTC.sol";
import {DeployDSCEngine} from "../script/DeployDSCEngine.s.sol";
import {ChainConfig} from "../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    //
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DscMinted(address indexed user, uint256 amountDscMinted, uint256 postHealthFactor);

    //
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);
    event DscBurned(address indexed onBehalfOf, uint256 amountDscBurned, uint256 postHealthFactor);

    //
    event LiquidationPerformed(
        address indexed collateral,
        address indexed user,
        address indexed liquidator,
        uint256 debtCovered,
        uint256 collateralTaken,
        uint256 bonusCollateral
    );

    DeployDSCEngine deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    ChainConfig chainConfig;
    MockToken weth;
    MockToken wbtc;
    MockToken junkToken = new MockToken("JUNK", "JUNK");
    MockV3Aggregator wethUsdPriceFeed;
    MockV3Aggregator wbtcUsdPriceFeed;

    address public owner;
    address public user = makeAddr("user");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_TOKEN_AMOUNT = 100e18;
    uint256 public constant MAX_DEBT_IN_WETH = 150000e18;
    uint256 public constant MAX_DEBT_IN_WBTC = 550000e18;
    uint256 public constant MAX_COLLATERAL_AMOUNT = 100e18;
    uint256 public constant DEBT_ALLOWED_IN_WETH = 100000e18; // 允许的贷款额度

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, engine, chainConfig) = deployer.run();
        owner = vm.addr(chainConfig.deployerPrivateKey);
        weth = MockToken(chainConfig.weth);
        wbtc = MockToken(chainConfig.wbtc);
        wethUsdPriceFeed = MockV3Aggregator(chainConfig.wethUsdPriceFeed);
        wbtcUsdPriceFeed = MockV3Aggregator(chainConfig.wbtcUsdPriceFeed);

        // 给alice和bob一些合法抵押物
        // 100 weth = 300000 usd = 150000 dsc
        weth.mint(alice, INITIAL_TOKEN_AMOUNT);
        weth.mint(bob, INITIAL_TOKEN_AMOUNT);
        // 100 wbtc = 1100000 usd = 550000 dsc
        wbtc.mint(alice, INITIAL_TOKEN_AMOUNT);
        wbtc.mint(bob, INITIAL_TOKEN_AMOUNT);
        junkToken.mint(alice, INITIAL_TOKEN_AMOUNT);
        junkToken.mint(bob, INITIAL_TOKEN_AMOUNT);
    }

    function test_engine_constructor() public view {
        assertEq(engine.getDsc(), address(dsc));

        assertEq(engine.getCollateralTokens().length, 2);

        assertEq(engine.getCollateralTokens()[0], chainConfig.weth);
        assertEq(engine.getCollateralTokens()[1], chainConfig.wbtc);

        assertEq(engine.getCollateralTokenPriceFeed(chainConfig.weth), chainConfig.wethUsdPriceFeed);
        assertEq(engine.getCollateralTokenPriceFeed(chainConfig.wbtc), chainConfig.wbtcUsdPriceFeed);
    }

    function test_fallback_receive_reverts() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);
        // 准备触发 receive：空 data，带 value
        vm.expectRevert(DSCEngine.DSCEngine__CallNotAllowed.selector);
        address(engine).call{value: 1 wei}("");

        // 准备触发 fallback：非空 data（也可以空 data，但 value 不可带，否则走 receive）
        vm.expectRevert(DSCEngine.DSCEngine__CallNotAllowed.selector);
        address(engine).call(abi.encodePacked(uint16(0x1234)));

        vm.stopPrank();
    }

    /**
     * @dev 用户成功抵押token，然后mint dsc
     */
    function test_depositCollateralAndMintDsc_success() public {
        vm.startPrank(alice);
        weth.approve(address(engine), MAX_COLLATERAL_AMOUNT);

        // 先计算预估抵押后的 HF
        // 先计算抵押对应的 USD 价值
        uint256 collateralValueUsd = engine.getUsdValue(chainConfig.weth, MAX_COLLATERAL_AMOUNT);
        // 再计算铸币之后的健康因子
        uint256 expectedHF = engine.calculateHealthFactor(MAX_DEBT_IN_WETH, collateralValueUsd);

        // 1. 期待第一个事件：CollateralDeposited
        //    topic0（签名），topic1(user)，topic2(token)，topic3(amount) 都要校验
        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(alice, address(weth), MAX_COLLATERAL_AMOUNT);

        // 2. 期待第二个事件：DscMinted
        //    校验签名、indexed user、data（amountDscMinted + postHealthFactor）
        vm.expectEmit(true, false, false, true);
        emit DscMinted(alice, MAX_DEBT_IN_WETH, expectedHF);

        engine.depositCollateralAndMintDsc(chainConfig.weth, MAX_COLLATERAL_AMOUNT, MAX_DEBT_IN_WETH);
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), 0);
        assertEq(engine.getCollateralBalanceOfUser(alice, chainConfig.weth), MAX_COLLATERAL_AMOUNT);
        assertEq(engine.getDscMinted(alice), MAX_DEBT_IN_WETH);
        assertEq(engine.getHealthFactor(alice), engine.getMinHealthFactor());
    }

    function test_depositCollateralAndMintDsc_reverts_DSCEngine__TokenNotAllowed() public {
        vm.startPrank(alice);
        weth.approve(address(engine), MAX_COLLATERAL_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(junkToken)));
        engine.depositCollateralAndMintDsc(address(junkToken), MAX_COLLATERAL_AMOUNT, MAX_DEBT_IN_WETH);

        vm.stopPrank();
    }

    function test_redeemCollateralForDsc_success() public {
        vm.startPrank(alice);
        // 抵押物品
        // alice 给 engine 授权 允许转走 MAX_COLLATERAL_AMOUNT 数量的 weth token。
        weth.approve(address(engine), MAX_COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(chainConfig.weth, MAX_COLLATERAL_AMOUNT, MAX_DEBT_IN_WETH);

        // 赎回物品
        // alice 给 engine 授权 允许转走 MAX_DEBT_IN_WETH 数量的 dsc token。
        dsc.approve(address(engine), MAX_DEBT_IN_WETH);

        // 期待第一个事件
        vm.expectEmit(true, false, false, true);
        emit DscBurned(alice, MAX_DEBT_IN_WETH, type(uint256).max);

        // 期待第二个事件
        vm.expectEmit(true, true, false, true);
        emit CollateralRedeemed(alice, alice, chainConfig.weth, MAX_COLLATERAL_AMOUNT);

        engine.redeemCollateralForDsc(chainConfig.weth, MAX_COLLATERAL_AMOUNT, MAX_DEBT_IN_WETH);
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
        assertEq(engine.getCollateralBalanceOfUser(alice, chainConfig.weth), 0);
        assertEq(engine.getDscMinted(alice), 0);
        assertEq(engine.getHealthFactor(alice), type(uint256).max);
    }

    /**
     * @dev 仅赎回：不改变债务，只执行 _redeemCollateral，触发 CollateralRedeemed 并做 HF 校验。
     */
    function test_redeemCollateral_success() public {
        vm.startPrank(alice);
        // 抵押物品
        // alice 给 engine 授权 允许转走 MAX_COLLATERAL_AMOUNT 数量的 weth token。
        weth.approve(address(engine), MAX_COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(chainConfig.weth, MAX_COLLATERAL_AMOUNT, DEBT_ALLOWED_IN_WETH);

        // 赎回物品
        // alice 给 engine 授权 允许转走 MAX_DEBT_IN_WETH 数量的 dsc token。
        dsc.approve(address(engine), MAX_DEBT_IN_WETH);

        vm.expectEmit(true, true, false, true);
        emit CollateralRedeemed(alice, alice, chainConfig.weth, 1);

        engine.redeemCollateral(chainConfig.weth, 1);
        vm.stopPrank();
    }

    /**
     * @dev liquidate(address collateral, address user, uint256 debtToCover)
     * 参数校验：
     * debtToCover == 0 → revert DSCEngine__NeedsMoreThanZero；
     * token 未允许 → revert DSCEngine__TokenNotAllowed；
     * 健康因子：
     * user HF ≥ MIN → revert DSCEngine__HealthFactorOk；
     * 	•	清算后若 user HF 未改善 → revert DSCEngine__HealthFactorNotImproved；
     * 	•	正常路径：
     * 	1.	计算 tokenAmountFromDebtCovered 和 bonusCollateral；
     * 	2.	执行 _redeemCollateral 给清算者，触发 CollateralRedeemed；
     * 	3.	执行 _burnDsc，触发 DscBurned；
     * 	4.	触发 LiquidationPerformed 事件；
     * 	•	重入保护：多次调用 liquidate 应受 nonReentrant 保护。
     */
    function test_liquidate_success() public {
        vm.startPrank(alice);
        // 抵押物品
        // alice 给 engine 授权 允许转走 MAX_COLLATERAL_AMOUNT 数量的 weth token。
        weth.approve(address(engine), MAX_COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(chainConfig.weth, MAX_COLLATERAL_AMOUNT, DEBT_ALLOWED_IN_WETH);

        // 赎回物品
        // alice 给 engine 授权 允许转走 MAX_DEBT_IN_WETH 数量的 dsc token。
        dsc.approve(address(engine), MAX_DEBT_IN_WETH);
        vm.stopPrank();

        // 更新priceFeed，模拟ETH下跌，触发清算 3000 -> 1500,此时 hf = 0.75
        wethUsdPriceFeed.updateAnswer(1500e8);

        // alice可以被清算，bob来清算
        vm.startPrank(bob);
        // Bob 选择部分清算 50_000 DSC
        uint256 debtToCover = 50_000e18;
        uint256 collateralTaken = engine.getCollateralAmountFromUsd(chainConfig.weth, debtToCover); // 33.3
        uint256 bonus = (collateralTaken * engine.getLiquidationBonus())/ engine.getLiquidationPrecision(); // 3.3
        uint256 totalCollateralTaken = collateralTaken + bonus; // 总共要拿走的weth数量，36.6

        // 计算之后的HF
        uint256 debtAfter = DEBT_ALLOWED_IN_WETH - debtToCover;
        uint256 collateralAfter = MAX_COLLATERAL_AMOUNT - totalCollateralTaken;
        uint256 collateralUsd = engine.getUsdValue(chainConfig.weth, collateralAfter);
        uint256 expectedPostHF = engine.calculateHealthFactor(debtAfter, collateralUsd);

        // 给bob dsc余额，然后授权给engine
        deal(address(dsc), bob, debtToCover);    // 作弊把余额写进去
        dsc.approve(address(engine), debtToCover);

        //  执行 _redeemCollateral 给清算者，触发 CollateralRedeemed；
        vm.expectEmit(true, true, false, true);
        emit CollateralRedeemed(alice, bob, chainConfig.weth, totalCollateralTaken);
        //  执行 _burnDsc，触发 DscBurned；
        vm.expectEmit(true, false, false, true);
        // alice的债务被减少，减少了多少债务，减少负债之后的健康因子
        emit DscBurned(alice, debtToCover, expectedPostHF);
        //  触发 LiquidationPerformed 事件；
        vm.expectEmit(true, true, true, true);
        emit LiquidationPerformed(address(weth), alice, bob, debtToCover, collateralTaken, bonus);

        engine.liquidate(address(weth), alice, debtToCover);
        vm.stopPrank();

        // 校验
    }
}
