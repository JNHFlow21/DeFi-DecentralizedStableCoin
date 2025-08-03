// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract TestDecentralizedStableCoin is Test {
    DecentralizedStableCoin public dsc;

    uint256 public num;

    function setUp() public {
        num = 1;
    }

    function testexm() public view{
        assertEq(num,1);
    }
}