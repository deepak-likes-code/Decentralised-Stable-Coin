// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
contract DSCEngine {

function depositCollateralAndMintDsc() external  {}

function depositCollateral() external{}

function redeemCollateralForDsc() external{}

function redeemCollateral() external{}

function healthFactor() external{}

function mintDsc() external{}

function burnDsc() external{}

function liquidate() external{}

}