// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
// import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";

// /*
//  * @title DSCEngine
//  * @author Patrick Collins (refactored)
//  *
//  * Core engine for an overcollateralized algorithmic stablecoin. Users deposit approved collateral,
//  * mint DSC, redeem collateral, and can be liquidated if undercollateralized.
//  */
// contract DSCEngine is ReentrancyGuard {
//     using OracleLib for AggregatorV3Interface;

//     ///////////////////
//     // Errors
//     ///////////////////
//     error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
//     error DSCEngine__NeedsMoreThanZero();
//     error DSCEngine__TokenNotAllowed(address token);
//     error DSCEngine__TransferFailed();
//     error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
//     error DSCEngine__MintFailed();
//     error DSCEngine__HealthFactorOk();
//     error DSCEngine__HealthFactorNotImproved();

//     ///////////////////
//     // Events
//     ///////////////////
//     event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
//     event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);
//     event DscMinted(address indexed user, uint256 amountDscMinted, uint256 postHealthFactor);
//     event DscBurned(address indexed onBehalfOf, uint256 amountDscBurned, uint256 postHealthFactor);
//     event LiquidationPerformed(
//         address indexed collateral,
//         address indexed user,
//         address indexed liquidator,
//         uint256 debtCovered,
//         uint256 collateralTaken,
//         uint256 bonusCollateral
//     );

//     ///////////////////
//     // Type declarations
//     ///////////////////
//     using OracleLib for AggregatorV3Interface;

//     ///////////////////
//     // State Variables
//     ///////////////////
//     DecentralizedStableCoin private immutable i_dsc;

//     // Thresholds are expressed with simple percentage math (e.g., 50 means 50%)
//     uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateral required to be safe (i.e., adjust by 50%)
//     uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus to liquidator
//     uint256 private constant LIQUIDATION_PRECISION = 100;

//     uint256 private constant MIN_HEALTH_FACTOR = 1e18; // health factor minimal acceptable (1 * 1e18)
//     uint256 private constant PRECISION = 1e18; // universal 
    
//     uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

//     uint256 private constant FEED_PRECISION = 1e8;

//     /// @dev Mapping of collateral token to its price feed
//     mapping(address collateralToken => address priceFeed) private s_priceFeeds;

//     /// @dev user -> token -> amount deposited
//     mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;

//     /// @dev user -> DSC debt minted
//     mapping(address user => uint256 amount) private s_DSCMinted;

//     /// @dev list of allowed collateral tokens (for enumeration)
//     address[] private s_collateralTokens;

//     ///////////////////
//     // Modifiers
//     ///////////////////
//     modifier moreThanZero(uint256 amount) {
//         if (amount == 0) {
//             revert DSCEngine__NeedsMoreThanZero();
//         }
//         _;
//     }

//     modifier isAllowedToken(address token) {
//         if (s_priceFeeds[token] == address(0)) {
//             revert DSCEngine__TokenNotAllowed(token);
//         }
//         _;
//     }

//     ///////////////////
//     // Constructor
//     ///////////////////
//     constructor(
//         address[] memory tokenAddresses,
//         address[] memory priceFeedAddresses,
//         address dscAddress
//     ) {
//         if (tokenAddresses.length != priceFeedAddresses.length) {
//             revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
//         }

//         for (uint256 i = 0; i < tokenAddresses.length; i++) {
//             s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
//             s_collateralTokens.push(tokenAddresses[i]);
//         }

//         i_dsc = DecentralizedStableCoin(dscAddress);
//     }

//     ///////////////////
//     // External Functions (state-changing)
//     ///////////////////

//     /**
//      * @notice 一次性抵押 + 铸币（组合），外部入口加防重入保护
//      */
//     function depositCollateralAndMintDsc(
//         address tokenCollateralAddress,
//         uint256 amountCollateral,
//         uint256 amountDscToMint
//     )
//         external
//         nonReentrant
//         moreThanZero(amountCollateral)
//         moreThanZero(amountDscToMint)
//         isAllowedToken(tokenCollateralAddress)
//     {
//         _depositCollateral(tokenCollateralAddress, amountCollateral, msg.sender);
//         _mintDsc(amountDscToMint, msg.sender);
//     }

//     /**
//      * @notice 赎回抵押并还债
//      */
//     function redeemCollateralForDsc(
//         address tokenCollateralAddress,
//         uint256 amountCollateral,
//         uint256 amountDscToBurn
//     )
//         external
//         nonReentrant
//         moreThanZero(amountCollateral)
//         isAllowedToken(tokenCollateralAddress)
//     {
//         _burnDsc(amountDscToBurn, msg.sender, msg.sender);
//         _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
//         _revertIfHealthFactorIsBroken(msg.sender);
//     }

//     /**
//      * @notice 只赎回抵押（必须保证债务安全）
//      */
//     function redeemCollateral(
//         address tokenCollateralAddress,
//         uint256 amountCollateral
//     )
//         external
//         nonReentrant
//         moreThanZero(amountCollateral)
//         isAllowedToken(tokenCollateralAddress)
//     {
//         _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
//         _revertIfHealthFactorIsBroken(msg.sender);
//     }

//     /**
//      * @notice 只还债（burn DSC）
//      */
//     function burnDsc(uint256 amount) external nonReentrant moreThanZero(amount) {
//         _burnDsc(amount, msg.sender, msg.sender);
//         _revertIfHealthFactorIsBroken(msg.sender); // 注：降低债务总是改善 health factor
//     }

//     /**
//      * @notice 清算：当用户 healthFactor < 1 时，清算者用自己的 DSC 覆盖部分债务，拿走其抵押 + bonus
//      */
//     function liquidate(
//         address collateral,
//         address user,
//         uint256 debtToCover
//     )
//         external
//         nonReentrant
//         isAllowedToken(collateral)
//         moreThanZero(debtToCover)
//     {
//         uint256 startingUserHealthFactor = _healthFactor(user);
//         if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
//             revert DSCEngine__HealthFactorOk();
//         }

//         // 1. 计算需要拿走的抵押数量（基于美元债务），再加 bonus
//         uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
//         uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
//         uint256 totalCollateralToTake = tokenAmountFromDebtCovered + bonusCollateral;

//         // 2. 从 user 取走抵押并给 liquidator（含 bonus）
//         _redeemCollateral(collateral, totalCollateralToTake, user, msg.sender);
//         // 3. 清算者用自己的 DSC 烧掉 user 的债务
//         _burnDsc(debtToCover, user, msg.sender);

//         uint256 endingUserHealthFactor = _healthFactor(user);
//         if (endingUserHealthFactor <= startingUserHealthFactor) {
//             revert DSCEngine__HealthFactorNotImproved();
//         }

//         // 4. 清算者自身安全性检查
//         _revertIfHealthFactorIsBroken(msg.sender);

//         emit LiquidationPerformed(
//             collateral,
//             user,
//             msg.sender,
//             debtToCover,
//             tokenAmountFromDebtCovered,
//             bonusCollateral
//         );
//     }

//     ///////////////////
//     // Public Functions (state-changing)
//     ///////////////////

//     /**
//      * @notice 铸造 DSC，前提是抵押充足
//      */
//     function mintDsc(uint256 amountDscToMint) public nonReentrant moreThanZero(amountDscToMint) {
//         _mintDsc(amountDscToMint, msg.sender);
//     }

//     /**
//      * @notice 抵押 ERC20 资产
//      */
//     function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
//         public
//         nonReentrant
//         moreThanZero(amountCollateral)
//         isAllowedToken(tokenCollateralAddress)
//     {
//         _depositCollateral(tokenCollateralAddress, amountCollateral, msg.sender);
//     }

//     ///////////////////
//     // Private / Internal State-changing Helpers
//     ///////////////////

//     function _depositCollateral(
//         address tokenCollateralAddress,
//         uint256 amountCollateral,
//         address from
//     ) internal {
//         s_collateralDeposited[from][tokenCollateralAddress] += amountCollateral;
//         emit CollateralDeposited(from, tokenCollateralAddress, amountCollateral);
//         bool success = IERC20(tokenCollateralAddress).transferFrom(from, address(this), amountCollateral);
//         if (!success) {
//             revert DSCEngine__TransferFailed();
//         }
//     }

//     function _mintDsc(uint256 amountDscToMint, address to) internal {
//         s_DSCMinted[to] += amountDscToMint;
//         _revertIfHealthFactorIsBroken(to);
//         bool minted = i_dsc.mint(to, amountDscToMint);
//         if (!minted) {
//             revert DSCEngine__MintFailed();
//         }
//         uint256 postHF = _healthFactor(to);
//         emit DscMinted(to, amountDscToMint, postHF);
//     }

//     function _redeemCollateral(
//         address tokenCollateralAddress,
//         uint256 amountCollateral,
//         address from,
//         address to
//     ) private {
//         s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
//         emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
//         bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
//         if (!success) {
//             revert DSCEngine__TransferFailed();
//         }
//     }

//     function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
//         s_DSCMinted[onBehalfOf] -= amountDscToBurn;

//         bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
//         if (!success) {
//             revert DSCEngine__TransferFailed();
//         }
//         i_dsc.burn(amountDscToBurn);
//         uint256 postHF = _healthFactor(onBehalfOf);
//         emit DscBurned(onBehalfOf, amountDscToBurn, postHF);
//     }

//     //////////////////////////////
//     // Private & Internal View & Pure Functions
//     //////////////////////////////

//     function _getAccountInformation(address user)
//         private
//         view
//         returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
//     {
//         totalDscMinted = s_DSCMinted[user];
//         collateralValueInUsd = getAccountCollateralValue(user);
//     }

//     function _healthFactor(address user) private view returns (uint256) {
//         (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
//         return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
//     }

//     /**
//      * @notice 获取某 token 某数量对应的美元价值（按内部统一 PRECISION 结果）
//      */
//     function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
//         address feedAddr = s_priceFeeds[token];
//         AggregatorV3Interface priceFeed = AggregatorV3Interface(feedAddr);
//         (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
//         uint8 feedDecimals = priceFeed.decimals(); // dynamic instead of assumption
//         // price has feedDecimals, want: (price * amount) normalized to PRECISION
//         // USD value = price * amount * (PRECISION) / (10 ** feedDecimals)
//         return (uint256(price) * amount * PRECISION) / (10 ** feedDecimals);
//     }

//     /**
//      * @notice 计算 health factor：越大越安全。债务为 0 时返回 max。
//      */
//     function _calculateHealthFactor(
//         uint256 totalDscMinted,
//         uint256 collateralValueInUsd
//     )
//         internal
//         pure
//         returns (uint256)
//     {
//         if (totalDscMinted == 0) return type(uint256).max;
//         uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
//         return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
//     }

//     function _revertIfHealthFactorIsBroken(address user) internal view {
//         uint256 userHealthFactor = _healthFactor(user);
//         if (userHealthFactor < MIN_HEALTH_FACTOR) {
//             revert DSCEngine__BreaksHealthFactor(userHealthFactor);
//         }
//     }

//     ///////////////////
//     // External & Public View & Pure
//     ///////////////////

//     function calculateHealthFactor(
//         uint256 totalDscMinted,
//         uint256 collateralValueInUsd
//     )
//         external
//         pure
//         returns (uint256)
//     {
//         return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
//     }

//     function getAccountInformation(address user)
//         external
//         view
//         returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
//     {
//         return _getAccountInformation(user);
//     }

//     function getUsdValue(address token, uint256 amount) external view returns (uint256) {
//         return _getUsdValue(token, amount);
//     }

//     function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
//         return s_collateralDeposited[user][token];
//     }

//     function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
//         for (uint256 i = 0; i < s_collateralTokens.length; i++) {
//             address token = s_collateralTokens[i];
//             uint256 amount = s_collateralDeposited[user][token];
//             totalCollateralValueInUsd += _getUsdValue(token, amount);
//         }
//         return totalCollateralValueInUsd;
//     }

//     /**
//      * @notice 反向计算：给定美元债务，用哪个数量的抵押去 cover（不含 bonus）
//      */
//     function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
//         address feedAddr = s_priceFeeds[token];
//         AggregatorV3Interface priceFeed = AggregatorV3Interface(feedAddr);
//         (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
//         uint8 feedDecimals = priceFeed.decimals();

//         // usdAmountInWei is scaled by PRECISION, price scaled by feedDecimals
//         // token amount = usd * (10 ** feedDecimals) / price / PRECISION
//         return (usdAmountInWei * (10 ** feedDecimals)) / (uint256(price) * PRECISION);
//     }

//     // Accessors for constants and state

//     function getPrecision() external pure returns (uint256) {
//         return PRECISION;
//     }

//     function getLiquidationThreshold() external pure returns (uint256) {
//         return LIQUIDATION_THRESHOLD;
//     }

//     function getLiquidationBonus() external pure returns (uint256) {
//         return LIQUIDATION_BONUS;
//     }

//     function getLiquidationPrecision() external pure returns (uint256) {
//         return LIQUIDATION_PRECISION;
//     }

//     function getMinHealthFactor() external pure returns (uint256) {
//         return MIN_HEALTH_FACTOR;
//     }

//     function getCollateralTokens() external view returns (address[] memory) {
//         return s_collateralTokens;
//     }

//     function getDsc() external view returns (address) {
//         return address(i_dsc);
//     }

//     function getCollateralTokenPriceFeed(address token) external view returns (address) {
//         return s_priceFeeds[token];
//     }

//     function getHealthFactor(address user) external view returns (uint256) {
//         return _healthFactor(user);
//     }
// }