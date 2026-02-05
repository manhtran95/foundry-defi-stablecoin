// SPDX-License-Identifier: MIT

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

pragma solidity ^0.8.18;

/**
 * @title DSCEngine
 * @author Manh Tran
 * This is minimal system, pegging 1 token == 1 USD.
 * Properties: Dollar pegged, Algorithmically stable, Exogenous Collateral
 * It's similar to DAI if DAI has no governance, no fees and only backed by WETH and WBTC
 * @notice this contract handles all logic for mining and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice this contract is loosely based on MakerDAO DSS (DAI) system
 */
contract DSCEngine {
    function depositCollateralAndMintDSC() external {}

    function depositCollateral() external {}

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view returns (uint256) {
        return 0;
    }
    
}