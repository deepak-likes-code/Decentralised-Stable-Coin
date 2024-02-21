//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethPriceFeed;
        address btcPriceFeed;
        address ethToken;
        address btcToken;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;
    uint8 private constant DECIMALS = 8;
    int256 private constant MOCK_BTC_PRICE = 40000e8;
    int256 private constant MOCK_ETH_PRICE = 2000e8;
    uint256 private DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaNetworkConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilNetworkConfig();
        }
    }

    function getSepoliaNetworkConfig() private view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            ethToken: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            btcToken: 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilNetworkConfig() private returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, MOCK_ETH_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, MOCK_BTC_PRICE);
        ERC20Mock wethToken = new ERC20Mock();
        ERC20Mock btcToken = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wethPriceFeed: address(ethUsdPriceFeed),
            btcPriceFeed: address(btcUsdPriceFeed),
            ethToken: address(wethToken),
            btcToken: address(btcToken),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
