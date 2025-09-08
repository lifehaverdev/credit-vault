// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";

contract SetBackend is Script {
    
    Foundation public foundation;

    function run() external {
        address backend = vm.envAddress("BACKEND_ADDRESS");
        bool isAuthorized = vm.envBool("SET_BACKEND_AUTHORIZED");

        address payable foundationAddr = payable(vm.envAddress("FOUNDATION_ADDRESS"));
        if (foundationAddr == address(0)) {
            console2.log("Please set FOUNDATION_ADDRESS in your .env file");
            return;
        }
        foundation = Foundation(foundationAddr);

        vm.startBroadcast();
        foundation.setMarshal(backend, isAuthorized);
        vm.stopBroadcast();

        console2.log("Backend status updated for address:");
        console2.logAddress(backend);
        console2.log("Authorization status:");
        console2.logBool(isAuthorized);
    }
} 