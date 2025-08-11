// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DecentralizedStableCoin
 * @author JNHFlow21
 * @notice This contract is the ERC20 implementation of the DecentralizedStableCoin
 * @dev This implements a stablecoin with the properties:
 * - 实现 ERC20Burnable 接口
 * - 实现 Ownable 接口
 * - 实现burn/mint 方法
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // errors
    error DecentralizedStableCoin__AmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();

    /**
     * @notice 构造函数，初始化 ERC20 名称与符号，并设置合约所有者
     * @dev 通过 `Ownable(msg.sender)` 指定初始 owner
     */
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    /**
     * @notice 仅所有者可销毁自身账户中的 DSC
     * @dev _burn 会检查 0 地址，因此这里只需校验两点：
     *  1. amount <= 0 revert
     *  2. amount > balanceOf(msg.sender) revert
     * @param amount 销毁数量
     */
    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }
        if (amount > balanceOf(msg.sender)) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(amount);
    }

    /**
     * @notice 仅所有者可铸造 DSC 到指定地址
     * @dev _mint 会检查 0 地址，因此这里只需校验一点：
     *  1. amount <= 0 revert
     * @param to 接收铸造代币的地址
     * @param amount 铸造数量
     * @return 成功与否
     */
    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }
        _mint(to, amount);
        return true;
    }
}
