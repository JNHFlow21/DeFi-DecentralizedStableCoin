// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployDSCEngine} from "../script/DeployDSCEngine.s.sol";
import {ChainConfig} from "../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSCEngine deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    ChainConfig chainConfig;
    ERC20Mock weth;
    ERC20Mock wbtc;

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
        weth = ERC20Mock(chainConfig.weth);
        wbtc = ERC20Mock(chainConfig.wbtc);

        // 给alice和bob一些合法抵押物 
        // 100 weth = 300000 usd = 150000 dsc
        weth.mint(alice, INITIAL_TOKEN_AMOUNT);
        weth.mint(bob, INITIAL_TOKEN_AMOUNT);
        // 100 wbtc = 1100000 usd = 550000 dsc
        wbtc.mint(alice, INITIAL_TOKEN_AMOUNT);
        wbtc.mint(bob, INITIAL_TOKEN_AMOUNT);
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
        engine.depositCollateralAndMintDsc(chainConfig.weth, MAX_COLLATERAL_AMOUNT, MAX_DEBT_IN_WETH);
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), 0);
        assertEq(engine.getCollateralBalanceOfUser(alice, chainConfig.weth), MAX_COLLATERAL_AMOUNT);
        assertEq(engine.getDscMinted(alice), MAX_DEBT_IN_WETH);
        assertEq(engine.getHealthFactor(alice), engine.getMinHealthFactor());
    }

    function test_depositCollateralAndMintDsc_reverts_when_not_enough_collateral() public {

    }

    
}