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
    // State variables
    mapping(address collateralToken => address priceFeed) private s_collateralTokenToPriceFeed;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    // address[] private s_collateralTokens;
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
     */
    function _mintDsc(uint256 amountDscToMint, address to) internal {

    }

    // private



    // view & pure functions



}
