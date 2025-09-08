// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";

contract SetFreeze is Script {
    
    Foundation public foundation;

    function run() external {
        address payable foundationAddr = payable(vm.envAddress("FOUNDATION_ADDRESS"));
        if (foundationAddr == address(0)) {
            console2.log("Please set FOUNDATION_ADDRESS in your .env file");
            return;
        }
        foundation = Foundation(foundationAddr);

        bool currentStatus = foundation.marshalFrozen();
        console2.log("Current marshalFrozen status:");
        console2.logBool(currentStatus);

        bool newStatus = !currentStatus;

        vm.startBroadcast();
        foundation.setFreeze(newStatus);
        vm.stopBroadcast();

        console2.log("Marshal frozen status updated to:");
        console2.logBool(newStatus);
    }
} 