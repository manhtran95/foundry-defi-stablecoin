// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 15 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    /////////////
    // Events////
    /////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeedsLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsMustBeTheSame.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // Price tests
    function testGetUsdValue() public view {
        uint256 amount = 1 ether;
        uint256 expectedUsd = 2000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, amount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;

        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    //////////////////////////////
    // Deposit collateral tests///
    //////////////////////////////
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsNotAllowed() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountCollateralValue() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValue);

        uint256 collateralBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 expectedCollateralBalance = STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL;
        assertEq(collateralBalance, expectedCollateralBalance);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////////////
    // Mint DSC tests/////////////
    //////////////////////////////
    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintBeforeCollateralIsDeposited() public {
        vm.startPrank(USER);
        uint256 expectedHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(1);
        vm.stopPrank();
    }

    function testRevertsIfMintBreaksHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        uint256 AMOUNT_COLLATERAL_IN_USD = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = 0.5 ether;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(AMOUNT_COLLATERAL_IN_USD);
        vm.stopPrank();
    }

    ///////////////////////////////////////////
    // Deposit Collateral And Mint DSC tests///
    ///////////////////////////////////////////
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        uint256 AMOUNT_COLLATERAL_IN_USD = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 validAmountDsc = AMOUNT_COLLATERAL_IN_USD / 2;
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, validAmountDsc);
        vm.stopPrank();
    }

    ////////////////////////////
    //Redeem Collateral tests///
    ////////////////////////////
    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 userBalanceBeforeRedeem = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalanceBeforeRedeem, AMOUNT_COLLATERAL);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalanceAfterRedeem = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    function testRevertsIfRedeemCollateralBreaksHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        uint256 AMOUNT_COLLATERAL_IN_USD = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 amountToMint = AMOUNT_COLLATERAL_IN_USD / 2;

        dsce.mintDsc(amountToMint);

        uint256 expectedHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////
    // Burn DSC tests///////////
    ////////////////////////////
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfBurnAmountIsMoreThanUserHas() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    function testCanBurnDscAfterMinting() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    ////////////////////////////
    // Liquidate tests///////////
    ////////////////////////////
    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);

        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_DSC_TO_MINT);

        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.liquidate(weth, USER, AMOUNT_DSC_TO_MINT);

        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 hardcordedExpectedWeth = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardcordedExpectedWeth);
    }

    function testLiquidatorHasNoMoreDsc() public liquidated {
        uint256 liquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);
        uint256 hardcordedExpectedDsc = 0;
        assertEq(liquidatorDscBalance, hardcordedExpectedDsc);
    }
    
    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }    
}
