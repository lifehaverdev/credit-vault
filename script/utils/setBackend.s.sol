// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {VaultRoot} from "src/VaultRoot.sol";

contract SetBackend is Script {
    
    VaultRoot public vaultRoot;

    function run() external {
        address backend = vm.envAddress("BACKEND_ADDRESS");
        bool isAuthorized = vm.envBool("SET_BACKEND_AUTHORIZED");

        address payable vaultRootAddr = payable(vm.envAddress("VAULT_ROOT_ADDRESS"));
        if (vaultRootAddr == address(0)) {
            console2.log("Please set VAULT_ROOT_ADDRESS in your .env file");
            return;
        }
        vaultRoot = VaultRoot(vaultRootAddr);

        vm.startBroadcast();
        vaultRoot.setBackend(backend, isAuthorized);
        vm.stopBroadcast();

        console2.log("Backend status updated for address:");
        console2.logAddress(backend);
        console2.log("Authorization status:");
        console2.logBool(isAuthorized);
    }
} 