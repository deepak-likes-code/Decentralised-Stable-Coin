//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] private priceFeeds;
    address[] private tokenAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethPriceFeed, address btcPriceFeed, address ethToken, address btcToken, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        priceFeeds = [wethPriceFeed, btcPriceFeed];
        tokenAddresses = [ethToken, btcToken];
        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin Dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(address(Dsc), tokenAddresses, priceFeeds);

        Dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (Dsc, engine, helperConfig);
    }
}
