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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceConverter} from "./_library/PriceConverter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DSCEngine is ReentrancyGuard {
    /**
     * !!! -------------- 注意精度问题--------------------
     * 代码中的 所有 DSC 精度都是 1e18， 因为ERC20的decimal是18
     * 所有 ETH/USDC 精度都是 1e8
     * 所有 抵押物 精度都是 1e18
     * 所有 债务 精度都是 1e18
     * 所有 健康因子 精度都是 1e18
     * 所有 抵押物价值 精度都是 1e18
     * 所有 债务价值 精度都是 1e18
     */

    ///////////////////
    // Errors
    ///////////////////

    /// @notice 传入的 token 地址数组和 price feed 地址数组长度不一致
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();

    /// @notice 数量必须大于 0
    error DSCEngine__NeedsMoreThanZero();

    /// @notice 该 token 不是被允许的抵押品
    /// @param token 地址
    error DSCEngine__TokenNotAllowed(address token);

    /// @notice ERC20 transfer/transferFrom 操作失败
    error DSCEngine__TransferFailed();

    /// @notice 操作导致用户健康因子低于最小安全值
    /// @param healthFactorValue 当前 health factor（缩放后）
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);

    /// @notice 铸造 DSC 失败
    error DSCEngine__MintFailed();

    /// @notice 目标用户 health factor 正常（用于拒绝清算）
    error DSCEngine__HealthFactorOk();

    /// @notice 清算后用户的 health factor 未改善（理论上不应发生）
    error DSCEngine__HealthFactorNotImproved();

    /// @notice 不允许调用
    error DSCEngine__CallNotAllowed();

    // Type declarations
    using PriceConverter for uint256;

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

    ///////////////////
    // Events
    ///////////////////

    /**
     * @notice 某用户抵押了 token
     * @param user 进行抵押的用户
     * @param token 抵押的 ERC20 token 地址
     * @param amount 抵押数量
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    /**
     * @notice 抵押被赎回（正常赎回或清算）
     * @param redeemFrom 原始抵押人
     * @param redeemTo 接收人（清算时可能不是原始人）
     * @param token 抵押 token 地址
     * @param amount 赎回数量
     */
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    /**
     * @notice 铸造了 DSC（增加债务）
     * @param user 受益人（债务被增加的账户）
     * @param amountDscMinted 铸造的 DSC 数量
     * @param postHealthFactor 铸造后该用户的健康因子
     */
    event DscMinted(address indexed user, uint256 amountDscMinted, uint256 postHealthFactor);

    /**
     * @notice DSC 被烧掉（还债 / 清算）
     * @param onBehalfOf 谁的债务减少了
     * @param amountDscBurned 烧掉的 DSC 数量
     * @param postHealthFactor 操作后该账户的健康因子
     */
    event DscBurned(address indexed onBehalfOf, uint256 amountDscBurned, uint256 postHealthFactor);

    /**
     * @notice 清算操作发生
     * @param collateral 被取走的抵押 token
     * @param user 被清算的用户
     * @param liquidator 执行清算的人
     * @param debtCovered 覆盖的 DSC 债务
     * @param collateralTaken 原始抵押（不含 bonus）
     * @param bonusCollateral 清算奖励部分
     */
    event LiquidationPerformed(
        address indexed collateral,
        address indexed user,
        address indexed liquidator,
        uint256 debtCovered,
        uint256 collateralTaken,
        uint256 bonusCollateral
    );

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

    receive() external payable {
        revert DSCEngine__CallNotAllowed();
    }

    fallback() external payable {
        revert DSCEngine__CallNotAllowed();
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
    ) external moreThanZero(amountCollateral) moreThanZero(amountDscToMint) isAllowedToken(tokenCollateralAddress) nonReentrant{
        _depositCollateral(tokenCollateralAddress, amountCollateral, msg.sender);
        _mintDsc(amountDscToMint, msg.sender);
    }

    /**
     * @dev 这个函数的功能是用户赎回抵押物，并还债
     * - 要注意的是 此时最后也要检查hf，避免还了一点钱，但是赎回了很多抵押物，导致账户不健康
     * 1. 还债 burn dsc
     * 2. 赎回 redeem token
     * 3. 检查 hf
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
        moreThanZero(amountDscToBurn)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice 只赎回抵押品（不减少债务）
     * @param tokenCollateralAddress 抵押 token 地址
     * @param amountCollateral 赎回数量
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice 只还债（burn DSC）
     * @param amount 想要 burn 的 DSC 数量
     */
    function burnDsc(uint256 amount) external moreThanZero(amount) nonReentrant{
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice 清算一个欠抵押的用户，用自己的 DSC 覆盖其债务并获取其抵押（含 bonus）
     * @param collateral 被用作抵押的 token 地址
     * @param user 被清算的目标用户
     * @param debtToCover 想覆盖的 DSC 债务量
     * 1. 首先判断 user的hf，是否能被清算
     * 2. 根据被清算人拥有的dsc数量，计算得到被清算人的对应抵押物数量1e18，不一定抵押物会被全部清算，有可能抵押物升值了，所以说是部分
     * 3. 清算人还能获得bonus，获得上面抵押物数量的10%
     * 4. 根据2，3计算出要 要转走的总抵押物数量，然后调用_redeem(),此时欠债人的抵押物已被转走
     * 5. _burn 掉 清算人的dsc，偿还债务
     * 6. 清算结束，分别判断下欠债人和偿还人 的 hf
     * @notice user mint 了100个dsc，抵押了价值200usd的eth，然后eth降价，hf不够，被清算。
     * @notice liquidator 用 自己的100个dsc 覆盖了 100个dsc 的债务，然后获得了 此时价值（100+10）usd 的eth（user 的抵押物）
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(collateral)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = _getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor >= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
        emit LiquidationPerformed(
            collateral, user, msg.sender, debtToCover, tokenAmountFromDebtCovered, bonusCollateral
        );
    }

    /**
     * @notice 单独铸造 DSC（不附带抵押操作）
     * @param amountDscToMint 铸造数量
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) {
        _mintDsc(amountDscToMint, msg.sender);
    }

    /**
     * @notice 单独抵押某个 token
     * @param tokenCollateralAddress 抵押 token 地址
     * @param amountCollateral 抵押数量
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _depositCollateral(tokenCollateralAddress, amountCollateral, msg.sender);
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
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
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
    function _depositCollateral(address tokenCollateralAddress, uint256 amountCollateral, address user) internal {
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
    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
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
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
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
        return amount.getUsdValue(s_collateralTokenToPriceFeed[token]);
    }

    /**
     * @dev 获取usd价值对应的抵押物token 数量，1e18精度
     */
    function _getTokenAmountFromUsd(address token, uint256 usdAmount) internal view returns (uint256) {
        return usdAmount.getTokenAmount(s_collateralTokenToPriceFeed[token]);
    }

    // private
    /**
     * @dev 偿还人用自己的dsc偿还债务人的债务
     * @param amountDscToBurn 要偿还的债务
     * @param onBehalfOf 债务人
     * @param dscFrom 偿还人
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // 1. 减少债务人债务
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        // 2. 偿还人将债务dsc转移到engine中
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // 3. engine burn这些债务代币
        i_dsc.burn(amountDscToBurn);
        // 4. 更新债务人的hf
        uint256 postHF = _healthFactor(onBehalfOf);
        emit DscBurned(onBehalfOf, amountDscToBurn, postHF);
    }

    /**
     * @dev 赎回抵押物
     * @param tokenCollateralAddress 抵押物地址
     * @param amountCollateral 赎回数量
     * @param from 赎回人
     * @param to 赎回目标地址
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // 1. 减少记录的抵押物数量
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // 2. 调用抵押物token的transfer方法，给to地址转抵押物
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // view & pure functions

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    // Accessors for constants and state

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_collateralTokenToPriceFeed[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }
}
