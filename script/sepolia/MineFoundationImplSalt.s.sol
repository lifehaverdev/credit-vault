// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {Foundation} from "src/Foundation.sol";

/// @notice Mines a vanity `salt` for deterministic deployment of the
///         `Foundation` implementation via `CREATE3.deployDeterministic`.
///         The vanity predicate is easily tweakable below.
///
/// Environment variables (all optional):
///   START – first numeric salt to try (default: 0)
///   END   – last numeric salt to try   (default: 1_000_000)
///
/// Usage example:
///   forge script script/sepolia/MineFoundationImplSalt.s.sol \
///     --fork-url $SEPOLIA_RPC \
///     --sender $IMPL_DEPLOYER
contract MineFoundationImplSalt is Script {
    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("Mining salt for deployer:", deployer);

        uint256 start = vm.envOr("START", uint256(0));
        uint256 end = vm.envOr("END", uint256(1_000_000));

        // Log the init-code hash for reference (bytecode is chain-agnostic).
        bytes32 initCodeHash = keccak256(type(Foundation).creationCode);
        console2.log("Foundation initCodeHash:");
        console2.logBytes32(initCodeHash);

        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(i);
            address predicted = CREATE3.predictDeterministicAddress(salt, deployer);

            // -----------------------------------------------------------------
            // >>> Vanity predicate <<<
            // Adjust this condition to taste. Current rule:
            // Top 4 hex chars of the address equal 0x1152 (same as Foundation).
            // -----------------------------------------------------------------
            if ((uint160(predicted) >> 140) == 0x1152) {
                console2.log("!! WOW !! Found matching salt:", i);
                console2.log("Predicted implementation address:", predicted);
                console2.logBytes32(salt);
                break;
            }

            if (i % 1000 == 0) {
                console2.log("Checked:", i);
            }
        }

        vm.resumeGasMetering();
        vm.stopBroadcast();
    }
}
