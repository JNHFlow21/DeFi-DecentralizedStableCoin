// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// import { AggregatorV3Interface } from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine 接口（NatSpec）
 * @notice 核心稳定币引擎接口：用户存入抵押品、铸造 DSC、赎回、还债与清算。
 * @dev 所有价值计算以 USD 为基准，使用 price feed 做估值，health factor 控制安全性。
 */
interface IDSCEngine {
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

    ///////////////////
    // 核心外部状态变更接口
    ///////////////////

    /**
     * @notice 抵押并同时铸造 DSC（原子操作）
     * @param tokenCollateralAddress 要抵押的 token 地址
     * @param amountCollateral 抵押数量（最小单位）
     * @param amountDscToMint 想要铸造的 DSC 数量
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external;

    /**
     * @notice 赎回抵押并还掉对应 DSC 债务
     * @param tokenCollateralAddress 赎回的抵押 token 地址
     * @param amountCollateral 想取回的抵押数量
     * @param amountDscToBurn 想烧掉（还掉）的 DSC 数量
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external;

    /**
     * @notice 只赎回抵押品（不减少债务）
     * @param tokenCollateralAddress 抵押 token 地址
     * @param amountCollateral 赎回数量
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    /**
     * @notice 只还债（burn DSC）
     * @param amount 想要 burn 的 DSC 数量
     */
    function burnDsc(uint256 amount) external;

    /**
     * @notice 清算一个欠抵押的用户，用自己的 DSC 覆盖其债务并获取其抵押（含 bonus）
     * @param collateral 被用作抵押的 token 地址
     * @param user 被清算的目标用户
     * @param debtToCover 想覆盖的 DSC 债务量
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external;

    /**
     * @notice 单独铸造 DSC（不附带抵押操作）
     * @param amountDscToMint 铸造数量
     */
    function mintDsc(uint256 amountDscToMint) external;

    /**
     * @notice 单独抵押某个 token
     * @param tokenCollateralAddress 抵押 token 地址
     * @param amountCollateral 抵押数量
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    ///////////////////
    // 只读 / 查询接口
    ///////////////////

    /**
     * @notice 计算给定债务和抵押价值下的 health factor（越大越安全）
     * @param totalDscMinted 已铸造的 DSC 债务（按内部精度）
     * @param collateralValueInUsd 抵押的 USD 价值（按内部精度）
     * @return healthFactor 缩放后的健康因子
     */
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256 healthFactor);

    /**
     * @notice 获取某个用户的债务和抵押价值
     * @param user 目标账户
     * @return totalDscMinted 该用户铸造的 DSC 债务
     * @return collateralValueInUsd 该用户抵押的总 USD 价值
     */
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd);

    /**
     * @notice 获取给定 token 数量的美元等价（内部统一 precision）
     * @param token 抵押 token 地址
     * @param amount token 数量（最小单位）
     * @return usdValue 等价的 USD 数值（缩放）
     */
    function getUsdValue(address token, uint256 amount) external view returns (uint256 usdValue);

    /**
     * @notice 获取某用户在某 token 上的抵押余额
     * @param user 用户地址
     * @param token 抵押 token 地址
     * @return amount 抵押数量
     */
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256 amount);

    /**
     * @notice 计算某用户所有抵押的总 USD 价值（遍历支持的抵押 token）
     * @param user 目标用户
     * @return totalCollateralValueInUsd 总 USD 抵押价值（缩放）
     */
    function getAccountCollateralValue(address user) external view returns (uint256 totalCollateralValueInUsd);

    /**
     * @notice 反向计算：给定美元债务，估算需要多少该 token 抵押（不含清算 bonus）
     * @param token 抵押 token 地址
     * @param usdAmountInWei 美元债务（按 internal precision 缩放）
     * @return tokenAmount 需要的 token 数量
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) external view returns (uint256 tokenAmount);

    /**
     * @notice 获取内部统一精度（用于外部对齐）
     */
    function getPrecision() external pure returns (uint256);

    /**
     * @notice 获取清算阈值系数（用于计算 adjusted collateral）
     */
    function getLiquidationThreshold() external pure returns (uint256);

    /**
     * @notice 获取清算奖励比例（liquidation bonus）
     */
    function getLiquidationBonus() external pure returns (uint256);

    /**
     * @notice 获取 liquidation precision（分母基准）
     */
    function getLiquidationPrecision() external pure returns (uint256);

    /**
     * @notice 获取最小健康因子（低于该值可被清算）
     */
    function getMinHealthFactor() external pure returns (uint256);

    /**
     * @notice 获取当前支持的所有抵押 token 列表
     * @return tokens 抵押 token 地址数组
     */
    function getCollateralTokens() external view returns (address[] memory tokens);

    /**
     * @notice 获取底层 DSC 合约地址
     * @return dscAddress DSC 合约地址
     */
    function getDsc() external view returns (address dscAddress);

    /**
     * @notice 查询某个抵押 token 对应的 price feed 地址
     * @param token 抵押 token 地址
     * @return feed price feed 地址
     */
    function getCollateralTokenPriceFeed(address token) external view returns (address feed);

    /**
     * @notice 获取某用户当前 health factor
     * @param user 用户地址
     * @return healthFactor 缩放后的健康因子
     */
    function getHealthFactor(address user) external view returns (uint256 healthFactor);
}
