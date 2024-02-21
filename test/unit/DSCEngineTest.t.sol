//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address wethPriceFeed;
    address ethTokenAddress;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC_20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethPriceFeed,, ethTokenAddress,,) = config.activeNetworkConfig();
        vm.deal(USER, STARTING_ERC_20_BALANCE);
    }

    /////////////////////////
    /// Constructor Tests////
    /////////////////////////
    function testRevertIfTokenLengthDoesntMatchPriceFeedsLength() public {
        address[] memory tokens = new address[](2);
        tokens[0] = ethTokenAddress;
        tokens[1] = ethTokenAddress;
        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = wethPriceFeed;
        DecentralizedStableCoin newDsc = new DecentralizedStableCoin();
        vm.expectRevert(DSCEngine.DSCEngine__TokenLengthMustEqualPriceFeedLength.selector);
        new DSCEngine(address(newDsc), tokens, priceFeeds);
    }

    ////////////////////////
    /// Price Feed Tests////
    ////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        IERC20(ethTokenAddress).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(ethTokenAddress, 0);
        vm.stopPrank();
    }

    function testGetUsdValue() external view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18;
        uint256 usdValue = engine.getUsdValue(ethTokenAddress, ethAmount);
        console.log("the usd value is ", usdValue);
        assert(usdValue == expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() external view {
        uint256 usdAmount = 100 ether;
        uint256 expectedTokenAmount = 0.05 ether;
        uint256 tokenAmount = engine.getTokenAmountFromUsd(ethTokenAddress, usdAmount);
        console.log("the token amount is ", tokenAmount);
        assert(tokenAmount == expectedTokenAmount);
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        engine.depositCollateral(address(randomToken), 10 ether);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(ethTokenAddress).approve(address(USER), AMOUNT_COLLATERAL);
        engine.depositCollateral(ethTokenAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateral() external depositCollateral {
        (uint256 DscMinted, uint256 collateral) = engine.getAccountInformation(USER);
        console.log("the DSC minted is ", DscMinted);
        assert(collateral == AMOUNT_COLLATERAL);
    }
}
