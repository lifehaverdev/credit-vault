// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {Foundation} from "src/Foundation.sol";

/// @notice Deterministically deploys the Foundation implementation using CREATE3.
///         Must be broadcast with the IMPL_DEPLOYER private key.
///         The salt is provided via $IMPL_SALT and should already be vanity-mined.
contract DeployFoundationImplementation is Script {
    function run() external {
        // ---------------------------------------------------------------------
        // Load config from environment
        // ---------------------------------------------------------------------
        bytes32 salt = vm.envBytes32("IMPL_SALT");

        // ---------------------------------------------------------------------
        // Broadcast transaction
        // ---------------------------------------------------------------------
        vm.startBroadcast();

        bytes memory initCode = type(Foundation).creationCode;
        address implementation = CREATE3.deployDeterministic(initCode, salt);

        console.log("Foundation implementation deployed at:", implementation);
        console2.logBytes32(salt);

        vm.stopBroadcast();
    }
}
