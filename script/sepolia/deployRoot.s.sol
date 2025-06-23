// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {VaultRoot} from "src/VaultRoot.sol";

// Using the same interface from the test for a type-safe deployment call.
interface ICreate2Factory {
    function deployCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address);
}

contract DeployVaultRoot is Script, Test {
    function run() external {
        address factory = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

        // The salt you successfully mined in the previous step.
        bytes32 salt = bytes32(uint256(29608));
        
        // Get the creation code for your contract and its hash.
        bytes memory bytecode = type(VaultRoot).creationCode;
        bytes32 initCodeHash = keccak256(bytecode);

        // Replicate the factory's internal `_guard` logic to calculate the salt it will actually use.
        bytes32 guardedSalt = keccak256(abi.encode(salt));

        // Calculate the final, expected deployment address.
        address expectedAddress = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), factory, guardedSalt, initCodeHash))
                )
            )
        );
        console.log("Expected deployment address:", expectedAddress);

        vm.startBroadcast();
        console.log("Deploying from account:", msg.sender);

        // Call the factory using the clean, type-safe interface.
        address deployedAddress = ICreate2Factory(factory).deployCreate2(salt, bytecode);
        
        console.log("!WOW! Deployed VaultRoot to:", deployedAddress);
        
        // Verify the on-chain deployment address matches our calculation. This ensures correctness.
        assertEq(deployedAddress, expectedAddress, "Deployment address mismatch!");

        vm.stopBroadcast();

    }
}
