// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DeployDSCEngine} from "../script/DeployDSCEngine.s.sol";
import {ChainConfig} from "../script/HelperConfig.s.sol";

contract DSCTest is Test {
    DeployDSCEngine deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    ChainConfig chainConfig;

    address public owner;
    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, engine, chainConfig) = deployer.run();
        owner = address(engine);
        vm.prank(owner);
        dsc.mint(owner, 100);
    }

    function test_dsc_constructor() public view{
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.decimals(), 18);
        assertEq(address(dsc.owner()), owner);
    }

    function test_dsc_mint_success() public {
        vm.startPrank(owner);
        bool success = dsc.mint(user, 100);
        assertEq(success, true);
        assertEq(dsc.balanceOf(user), 100);
        vm.stopPrank();
    }

    function test_dsc_burn_success() public {
        // 只能烧自己的币，也就是只能烧owner的币，若要销毁user的币，需要user先转给owner
        vm.startPrank(owner);
        dsc.burn(10);
        assertEq(dsc.balanceOf(owner), 90);
        vm.stopPrank();
    }

    function test_dsc_mint_reverts_when_amount_is_zero() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeGreaterThanZero.selector);
        dsc.mint(owner, 0);
        vm.stopPrank();
    }

    function test_dsc_burn_reverts_when_amount_is_zero() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeGreaterThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function test_dsc_burn_reverts_when_amount_exceeds_balance() public {
        vm.startPrank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(110);
        vm.stopPrank();
    }
    
}