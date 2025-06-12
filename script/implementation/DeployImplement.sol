// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {VaultRoot} from "../../src/VaultRoot.sol";

contract DeployLogic is Script {
    function run() external {
        vm.startBroadcast();
        VaultRoot logic = new VaultRoot();
        console.log("Logic deployed at:", address(logic));
        vm.stopBroadcast();
    }
}
