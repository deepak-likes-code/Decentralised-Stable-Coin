// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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

/**
 * @title Decentralized Stable Coin Engine
 * @author Deepak Komma
 * @notice This contract is the core of the DSC engine and is supposed to handle all the logic for deposits, withdrawals, and minting of the DSC
 * @notice This contract is loosely based on the MakerDAO engine
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////////////////
    ////////// Errors /////////////
    ///////////////////////////////

    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenLengthMustEqualPriceFeedLength();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotOk();

    /////////////////////////////////////
    ////////// State Variables //////////
    /////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDAATION_BONUS = 10;

    DecentralizedStableCoin immutable i_decentralizedStableCoin;
    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeeds;
    mapping(address user => mapping(address tokenAddress => uint256 amount)) private s_userCollateralBalances;
    mapping(address user => uint256 amount) private s_DscMinted;
    address[] private s_collateralTokens;

    ///////////////////////////////
    ////////// Events //////////
    ///////////////////////////////
    event DepositCollateral(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event RedeemCollateral(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenAddress, uint256 amount
    );
    ///////////////////////////////
    ////////// Modifiers //////////
    ///////////////////////////////

    modifier amountIsGreaterThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier tokenIsAllowed(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    ///////////////////////////////
    ////////// Functions //////////
    ///////////////////////////////

    constructor(address _decentralisedStableCoin, address[] memory allowedTokens, address[] memory priceFeeds) {
        if (allowedTokens.length != priceFeeds.length) {
            revert DSCEngine__TokenLengthMustEqualPriceFeedLength();
        }
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            s_priceFeeds[allowedTokens[i]] = priceFeeds[i];
            s_collateralTokens.push(allowedTokens[i]);
        }
        if (_decentralisedStableCoin != address(0)) {
            i_decentralizedStableCoin = DecentralizedStableCoin(_decentralisedStableCoin);
        } else {
            i_decentralizedStableCoin = new DecentralizedStableCoin();
        }
    }

    ////////////////////////////////////////
    ////////// External Functions //////////
    ////////////////////////////////////////

    /**
     *
     * @param collateralTokenAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function is a convenience function that allows the user to deposit collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address collateralTokenAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(collateralTokenAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenAddress The address of the token to be deposited as collateral
     * @param depositAmount The amount of the token to be deposited as collateral
     */
    function depositCollateral(address tokenAddress, uint256 depositAmount)
        public
        amountIsGreaterThanZero(depositAmount)
        tokenIsAllowed(tokenAddress)
        nonReentrant
    {
        s_userCollateralBalances[msg.sender][tokenAddress] += depositAmount;
        emit DepositCollateral(msg.sender, tokenAddress, depositAmount);
        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), depositAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to be redeemed
     * @param amountCollateral The amount of the token to be redeemed
     * @param dscToBurn The amount of DSC to burn
     * @notice This function allows the user to redeem collateral and burn DSC in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 dscToBurn)
        external
    {
        burnDsc(dscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountIsGreaterThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function healthFactor() external {}

    function mintDsc(uint256 amountDscToMint) public amountIsGreaterThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        // if they minted too much DSC, then revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_decentralizedStableCoin.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public amountIsGreaterThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param collateral The address of the ERC20 collateral to be liquidated
     * @param user The address of the user to be liquidated. Their health factor must be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can parially liquidate the user
     * @notice Youll get liquidation bonus on liquidating the users funds
     * @notice This function assumes that this protocol has 200% overcollateralization
     * @notice One bug could be that the price plummets below 100% and their would be no incentivation for the liquidator to liquidate the position
     * Follows checks-effects-interactions pattern
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        amountIsGreaterThanZero(debtToCover)
        nonReentrant
    {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        // give them 10% bonus
        // so give the liquidator 10% more of the collateral
        // we should implement a feature to liquidate even when the protocol is insolvent
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDAATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        // burn the DSC
        _burnDsc(debtToCover, user, msg.sender);

        // check if the health factor is ok
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotOk();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////////////////////
    //// Private and Internal Functions ////
    ////////////////////////////////////////

    function _burnDsc(uint256 amountOfDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DscMinted[onBehalfOf] -= amountOfDscToBurn;
        bool success = i_decentralizedStableCoin.transferFrom(onBehalfOf, address(this), amountOfDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_decentralizedStableCoin.burn(amountOfDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_userCollateralBalances[from][tokenCollateralAddress] -= amountCollateral;

        emit RedeemCollateral(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getCollateralValueInUsd(address user) private view returns (uint256) {}

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        totalCollateralValueInUsd = getCollateralValueInUsd(user);
    }

    /**
     * Returns the health factor of a user and states how close they are to being liquidated
     * @param user The address of the user to check the health factor of
     */
    function _healthFactor(address user) private view returns (uint256) {
        //total DSC minted
        //total collateral value in USD
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////
    //// Public View Functions /////////////
    ////////////////////////////////////////

    function getTokenAmountFromUsd(address collateral, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralValueInUsd(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;
        // loop through all the tokens that the users might have and get the price feed for each token
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_userCollateralBalances[user][tokenAddress];

            // get the price feed for each token
            // multiply the amount of the token by the price feed
            // add it to the total
            uint256 collateralAmountInUsd = getUsdValue(tokenAddress, amount);
            totalCollateralValueInUsd += collateralAmountInUsd;
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address tokenAddress, uint256 amount) public view returns (uint256 priceInUsd) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        priceInUsd = ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        (totalDscMinted, totalCollateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address tokenAddress) public view returns (uint256) {
        return s_userCollateralBalances[user][tokenAddress];
    }
}
