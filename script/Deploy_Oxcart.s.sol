// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";

import "../src/Oxcart.sol";

contract DeployOxcart is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Oxcart oxcart = new Oxcart();
        UnsafeUpgrades.deployTransparentProxy(
            address(oxcart), msg.sender, abi.encodeCall(Oxcart.initialize, msg.sender)
        );

        vm.stopBroadcast();
    }
}
