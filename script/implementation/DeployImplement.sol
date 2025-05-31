// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {AiCreditVault} from "../../src/implementation/CreditVault.sol";

contract DeployLogic is Script {
    function run() external {
        vm.startBroadcast();
        AiCreditVault logic = new AiCreditVault();
        console.log("Logic deployed at:", address(logic));
        vm.stopBroadcast();
    }
}
