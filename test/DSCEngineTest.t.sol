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

    address public owner;
    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, engine, chainConfig) = deployer.run();
        owner = vm.addr(chainConfig.deployerPrivateKey);
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

    
}