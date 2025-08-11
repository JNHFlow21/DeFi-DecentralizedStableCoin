// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    /**
     * @notice 简单的 ERC20 Mock，用于本地/测试环境
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /**
     * @notice 向指定地址铸造代币（测试用途）
     * @param to 接收者
     * @param amount 数量
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @notice 从指定地址销毁代币（测试用途）
     * @param from 源地址
     * @param amount 数量
     */
    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
