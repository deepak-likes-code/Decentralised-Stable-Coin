//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethAddress;
    address wBtcAddress;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        targetContract(address(engine));
        (,, ethAddress, wBtcAddress,) = config.activeNetworkConfig();
    }

    function invariant_protocolMustHaveMoreValueThanCollateralSupplied() public {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethSupplied = IERC20(ethAddress).balanceOf(address(engine));
        uint256 totalWBtcSupplied = IERC20(wBtcAddress).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(ethAddress, totalWethSupplied);
        uint256 wBtcValue = engine.getUsdValue(wBtcAddress, totalWBtcSupplied);

        console.log("Total Supply: ", totalSupply);
        console.log("Total Weth Supplied: ", totalWethSupplied);
        console.log("Total WBtc Supplied: ", totalWBtcSupplied);

        uint256 totalValue = wethValue + wBtcValue;
        assert(totalSupply > totalValue);
    }
}
