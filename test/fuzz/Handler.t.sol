// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    uint256 public timesRedeemIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public wethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory tokenAddresses = dsce.getCollateralTokens();
        weth = ERC20Mock(tokenAddresses[0]);
        wbtc = ERC20Mock(tokenAddresses[1]);

        wethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 dscMinted, uint256 accountCollateralValue) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = int256(accountCollateralValue) / 2 - int256(dscMinted);
        if (maxDscToMint < 0) return;
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // This breaks the invariant when the price of the collateral plummets
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     wethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        (uint256 dscMinted,) = dsce.getAccountInformation(msg.sender);
        uint256 accountCollateralValue = dsce.getUsdValue(address(collateral), collateralBalance);
        int256 maxCollateralValueToRedeem = int256(accountCollateralValue) - int256(dscMinted) * 2;
        if (maxCollateralValueToRedeem < 0) return;
        uint256 maxCollateralToRedeem = dsce.getTokenAmountFromUsd(address(collateral), uint256(maxCollateralValueToRedeem));
        
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        timesRedeemIsCalled++;
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}