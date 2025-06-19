// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {VaultRoot} from "src/VaultRoot.sol";

contract DeployVaultRoot is Script {
    function run() external {
        vm.startBroadcast();

        // Your pre-mined salt
        bytes32 salt = bytes32(uint256(62301));

        // Deterministic CREATE2 deployment
        VaultRoot impl = new VaultRoot{salt: salt}();
        console2.log("!WOW! Deployed VaultRoot to:", address(impl));

        vm.stopBroadcast();
    }
}
