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

    /////////////////////////////////////
    ////////// State Variables //////////
    /////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin immutable i_decentralizedStableCoin;
    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeeds;
    mapping(address user => mapping(address tokenAddress => uint256 amount)) private s_userCollateralBalances;
    mapping(address user => uint256 amount) private s_DscMinted;
    address[] private s_collateralTokens;

    ///////////////////////////////
    ////////// Events //////////
    ///////////////////////////////
    event DepositCollateral(address indexed user, address indexed tokenAddress, uint256 indexed amount);

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
        i_decentralizedStableCoin = DecentralizedStableCoin(_decentralisedStableCoin);
    }

    ////////////////////////////////////////
    ////////// External Functions //////////
    ////////////////////////////////////////
    function depositCollateralAndMintDsc() external {}

    /**
     * @param tokenAddress The address of the token to be deposited as collateral
     * @param depositAmount The amount of the token to be deposited as collateral
     */
    function depositCollateral(address tokenAddress, uint256 depositAmount)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function healthFactor() external {}

    function mintDsc(uint256 amountDscToMint) external amountIsGreaterThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        // if they minted too much DSC, then revert

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    ////////////////////////////////////////
    //// Private and Internal Functions ////
    ////////////////////////////////////////

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
        priceInUsd = (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }
}
