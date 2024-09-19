// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";

import "../src/Oxcart_v2.sol";

contract UpgradeOxcart is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Upgrade the proxy to use the new implementation contract
        address proxyAddress = vm.envAddress("PROXY_ADDRESS_MAIN");
        Upgrades.upgradeProxy(proxyAddress, "Oxcart_v2.sol", "");

        vm.stopBroadcast();
    }
}