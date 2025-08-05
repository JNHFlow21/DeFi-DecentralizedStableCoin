// SPDX-License-Identifier: MIT

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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IDSCEngine} from "./interface/IDSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngine is IDSCEngine {

    /** !!! -------------- 注意精度问题-------------------- 
     * 代码中的 所有 DSC 精度都是 1e18， 因为ERC20的decimal是18
     * 所有 ETH/USDC 精度都是 1e8
     * 所有 抵押物 精度都是 1e18
     * 所有 债务 精度都是 1e18
     * 所有 健康因子 精度都是 1e18
     * 所有 抵押物价值 精度都是 1e18
     * 所有 债务价值 精度都是 1e18
    */


    // State variables

    // Thresholds are expressed with simple percentage math (e.g., 50 means 50%)
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateral required to be safe (i.e., adjust by 50%)
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus to liquidator
    uint256 private constant LIQUIDATION_PRECISION = 100;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // health factor minimal acceptable (1 * 1e18)
    uint256 private constant PRECISION = 1e18; // universal internal scaling for ratios

    mapping(address collateralToken => address priceFeed) private s_collateralTokenToPriceFeed;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    /**
     * @dev 记录用户 mint 的dsc数量。
     *  ERC20 的decimal是18，所以mint 2 个dsc时，s_DSCMinted[user] = 2e18
     */
    mapping(address user => uint256 amount) private s_DSCMinted;
    /**
     * @dev 记录所有允许的抵押物
     *  - 因为mapping不能遍历，所以需要一个address[]来辅助遍历
     */
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_collateralTokenToPriceFeed[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }


    // constructor
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // 首先检查长度是否一致，不一致直接revert
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // 知道了抵押物地址和priceFeed地址，我们就可以将它们一一对应起来，存入mapping
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_collateralTokenToPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // 实例化dsc合约
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // external
    /**
     * @dev 这个函数的功能是用户抵押token，并mint dsc。
     * 作为外部入口我们需要检查：
     *  1. 检查抵押token是否合法
     *  2. 检查抵押token数量是否大于0
     *  3. 检查mint的dsc数量是否大于0
     * 之后调用内部函数：
     *  1.抵押token
     *  2.mint dsc
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external 
    moreThanZero(amountCollateral)
    moreThanZero(amountDscToMint)
    isAllowedToken(tokenCollateralAddress)
    {
        _depositCollateral(tokenCollateralAddress, amountCollateral, msg.sender);
        _mintDsc(amountDscToMint, msg.sender);
    }


    // public

    /**
     * @dev 获取用户的总抵押物价值
     *  - mapping 不能遍历 所有需要一个address[]来辅助遍历
     *  1. 遍历所有合法抵押物，s_collateralTokens
     *  2. 检查 user 是否抵押了 这种抵押物token 以及 抵押数量amount
     *  3. 调用_getUsdValue计算每个token的USD价值
     *  4. 将每个token的USD价值相加，得到总抵押物价值totalCollateralValueInUsd，然后返回
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd){
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }


    // internal

    /**
     * @dev 这个函数的功能是抵押token
     *  1. 更新s_collateralDeposited，记录该用户的抵押物以及抵押物数量，并且emit
     *  2. 调用IERC20的transferFrom方法，将用户抵押的token从用户地址转移到合约地址，如果失败revert
     *  3. transferFrom和transfer的区别就是，前者是第三方代转帐会检查allowance，所以需要先approve，后者是账户所有者自己转账不会检查allowance
     */
    function _depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address user
    ) internal {
        s_collateralDeposited[user][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(user, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(user, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev 这个函数的功能是mint dsc
     *  1. 先把债务计入系统，然后检查健康因子，使用最新的债务情况判断此次是否准许借贷
     *  2. 如果准许借贷，则mint dsc，并emit事件，打印出mint的dsc数量和健康因子
     */
    function _mintDsc(uint256 amountDscToMint, address to) internal {
        s_DSCMinted[to] += amountDscToMint;
        _revertIfHealthFactorIsBroken(to);
        bool minted = i_dsc.mint(to, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        uint256 postHF = _healthFactor(to);
        emit DscMinted(to, amountDscToMint, postHF);
    }

    /**
     * @dev 返回此时的hf
     * 1. 调用内部函数 得到用户的总负债 和总抵押
     * 2. 调用内部函数，将上面得到的结果作为参数，计算此时的hf
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @dev 返回此时的hf，如果小于最低 hf revert
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @dev 获取用户的 总负债 和 总抵押物价值
     * - 总负债：mint的dsc 数量
     * - 总抵押物价值：ETH/USDC 此时的 USD价值
     */
    function _getAccountInformation(address user) internal view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @dev 计算此时的hf，hf 是1e18精度，越大越健康
     *  1. 如果user没有mint dsc，则返回 max
     *  2. 否则，先计算有效抵押额度，因为是超额抵押
     *      collateralValueInUsd = 200e18
     *      LIQUIDATION_THRESHOLD = 50  / LIQUIDATION_PRECISION = 100
     *      先乘后除 collateralAdjustedForThreshold = 200e18 * 50 / 100 = 100e18
     *  3. 最后，计算 hf = collateralAdjustedForThreshold / totalDscMinted = 100e18 / 100e18 = 1 还要对齐精度所以* PRECISION = 1e18
     */
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal view returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
     }

    /**
     * @dev 获取token（抵押物）的USD价值 1e18精度
     *  1. 调用priceFeed的getPrice方法，获取token的USD价值
     *  2. 将token的USD价值乘以amount，得到token的USD价值
     *  3. 返回token的USD价值
     */
     function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
 
     }

    // private



    // view & pure functions



}
