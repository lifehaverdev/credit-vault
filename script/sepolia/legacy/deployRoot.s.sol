// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {Foundation} from "src/Foundation.sol";

// Using the same interface from the test for a type-safe deployment call.
interface ICreate2Factory {
    function deployCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address);
}

contract DeployFoundation is Script, Test {
    function run() external {
        address factory = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
        address ownerNFT = vm.envAddress("TEST_OWNER_NFT");
        uint256 ownerTokenId = vm.envUint("TEST_OWNER_TOKEN_ID");
        address charterBeacon = vm.envAddress("CHARTER_BEACON");

        // The salt you successfully mined in the previous step.
        bytes32 salt = bytes32(vm.envUint("SALT"));
        
        // Get the creation code for your contract and its hash.
        bytes memory bytecode = abi.encodePacked(type(Foundation).creationCode, abi.encode(ownerNFT, ownerTokenId));
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
        Foundation(payable(deployedAddress)).initialize(ownerNFT, ownerTokenId, charterBeacon);
        
        console.log("!WOW! Deployed Foundation to:", deployedAddress);
        
        // Verify the on-chain deployment address matches our calculation. This ensures correctness.
        assertEq(deployedAddress, expectedAddress, "Deployment address mismatch!");

        vm.stopBroadcast();

    }
}
