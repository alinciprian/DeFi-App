//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {MockFailedTransfer} from "./mocks/MockFailedTransfer.sol";
import {MockMoreDebtDSC} from "./mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 50 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    ////////////////////////////////
    ///Constructor Tests ///////////
    ////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testIfPriceFeedsInitializesCorrectly() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);

        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        dsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        address toBeCompared = dsce.getPriceFeeds(tokenAddresses[0]);
        address[] memory collateralTokens = dsce.getSupportedCollateralTokens();

        assertEq(toBeCompared, priceFeedAddresses[0]);
        assertEq(dsce.getPriceFeeds(tokenAddresses[1]), priceFeedAddresses[1]);
        assertEq(collateralTokens.length, 2);
        assertEq(address(dsce.getDscAddress()), address(dsc));
    }

    function testDepozitCollateralAndMintDsc() public {
        uint256 MAXIMUM_DSC_TO_MINT = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MAXIMUM_DSC_TO_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = MAXIMUM_DSC_TO_MINT;
        uint256 expectedCollateralValue = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(expectedCollateralValue, AMOUNT_COLLATERAL);
    }

    //////////////////////////////
    /////depositCollateral Tests//
    //////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnaprovvedCollateral() public {
        ERC20Mock testToken = new ERC20Mock("test", "test", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(testToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;

        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

    ///////////////////////////////
    /////MINT TEST/////////////////
    ///////////////////////////////

    function testRevertsIfMintAmountZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorBroken() public depositedCollateral {
        uint256 maxThatShouldBeAllowedToMint = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;
        uint256 shouldNotBeAllowedToMint = maxThatShouldBeAllowedToMint + 1;
        vm.prank(USER);
        vm.expectRevert();
        dsce.mintDsc(shouldNotBeAllowedToMint);
        vm.stopPrank();
    }

    //////////////////////////////
    //////BurnDsc function////////
    //////////////////////////////

    function testIfDscIsBurned() public depositedCollateral {
        uint256 mintAmount = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;

        vm.startPrank(USER);

        dsce.mintDsc(mintAmount);
        (uint256 beforeBurnDscAmount, uint256 beforeBurnCollateralValueInUsd) = dsce.getAccountInformation(USER);
        dsc.approve(address(dsce), mintAmount);
        dsce.burnDsc(beforeBurnDscAmount / 2);
        (uint256 afterBurnDscAmount, uint256 afterBurnCollateralValueInUsd) = dsce.getAccountInformation(USER);

        vm.stopPrank();

        assertEq(beforeBurnDscAmount, 2 * afterBurnDscAmount);
        assertEq(beforeBurnCollateralValueInUsd, afterBurnCollateralValueInUsd);
    }

    ////////////////////////////
    /////Redeem Collateral//////
    ////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public {
        uint256 mintAmount = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        uint256 userBalanceBefore = ERC20Mock(weth).balanceOf(USER);
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL + userBalanceBefore);
        vm.stopPrank();
    }

    function testRedeemFailIfBreaksHealthFactor() public {
        uint256 mintAmount = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
        vm.expectRevert();
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL / 10);

        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        // Act / Assert
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // function testMustImproveHealthFactorOnLiquidation() public {
    //     // Arrange - Setup
    //     uint256 mintAmount = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;
    //     MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
    //     tokenAddresses = [weth];
    //     priceFeedAddresses = [ethUsdPriceFeed];
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
    //     mockDsc.transferOwnership(address(mockDsce));
    //     // Arrange - User
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
    //     mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
    //     vm.stopPrank();

    //     // Arrange - Liquidator
    //     collateralToCover = 1 ether;
    //     ERC20Mock(weth).mint(liquidator, collateralToCover);

    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
    //     uint256 debtToCover = 10 ether;
    //     mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
    //     mockDsc.approve(address(mockDsce), debtToCover);
    //     // Act
    //     int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    //     // Act/Assert
    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    //     mockDsce.liquidate(weth, user, debtToCover);
    //     vm.stopPrank();
    // }

    function testGestUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }
}
