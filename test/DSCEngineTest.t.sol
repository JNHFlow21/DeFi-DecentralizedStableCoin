// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {MockToken} from "../src/mocks/mock_WETH_WBTC.sol";
import {DeployDSCEngine} from "../script/DeployDSCEngine.s.sol";
import {ChainConfig} from "../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DscMinted(address indexed user, uint256 amountDscMinted, uint256 postHealthFactor);

    DeployDSCEngine deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    ChainConfig chainConfig;
    MockToken weth;
    MockToken wbtc;

    MockToken junkToken = new MockToken("JUNK", "JUNK");

    address public owner;
    address public user = makeAddr("user");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_TOKEN_AMOUNT = 100;
    uint256 public constant MAX_DEBT_IN_WETH = 150000;
    uint256 public constant MAX_DEBT_IN_WBTC = 550000;
    uint256 public constant MAX_COLLATERAL_AMOUNT = 100;

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, engine, chainConfig) = deployer.run();
        owner = vm.addr(chainConfig.deployerPrivateKey);
        weth = MockToken(chainConfig.weth);
        wbtc = MockToken(chainConfig.wbtc);

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
    function test_redeemCollateral_success() public {}
}
