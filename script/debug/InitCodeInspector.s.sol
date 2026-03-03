// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {CharteredFundImplementation} from "../../src/CharteredFundImplementation.sol";

contract InitCodeInspector is Script {
    function run() external view {
        // Use the exact same values from the user's JavaScript implementation
        address FOUNDATION_ADDRESS = 0x01152530028bd834EDbA9744885A882D025D84F6;
        address CHARTER_BEACON_ADDRESS = 0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C;
        address OWNER_ADDRESS = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
        
        inspectBeaconProxyInitCode(CHARTER_BEACON_ADDRESS, FOUNDATION_ADDRESS, OWNER_ADDRESS);
    }
    
    function inspectBeaconProxyInitCode(
        address beacon,
        address foundation,
        address owner
    ) public pure returns (
        bytes memory initCode,
        bytes32 initCodeHash,
        bytes memory prefixBytes,
        bytes memory beaconBytes,
        bytes memory runtimeCode1,
        bytes memory runtimeCode2,
        bytes memory runtimeCode3,
        bytes memory argsBytes
    ) {
        // Encode args exactly like Foundation.computeCharterAddress
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955), // initialize selector
            foundation,
            owner
        );
        
        // Generate init code using LibClone
        initCode = LibClone.initCodeERC1967BeaconProxy(beacon, args);
        initCodeHash = keccak256(initCode);
        
        // Break down the init code into components
        // The init code structure for ERC1967 beacon proxy with args is:
        // [prefix][beacon][runtime_code_1][runtime_code_2][runtime_code_3][args]
        
        // Extract components based on the known structure
        // This is a simplified breakdown - the actual structure is more complex
        prefixBytes = new bytes(0x52); // First 82 bytes are prefix
        beaconBytes = new bytes(20);  // Next 20 bytes are beacon address
        runtimeCode1 = new bytes(32); // Runtime code part 1
        runtimeCode2 = new bytes(32); // Runtime code part 2  
        runtimeCode3 = new bytes(32); // Runtime code part 3
        argsBytes = new bytes(args.length); // Args at the end
        
        // Copy the components
        for (uint256 i = 0; i < prefixBytes.length && i < initCode.length; i++) {
            prefixBytes[i] = initCode[i];
        }
        
        for (uint256 i = 0; i < beaconBytes.length && i + prefixBytes.length < initCode.length; i++) {
            beaconBytes[i] = initCode[i + prefixBytes.length];
        }
        
        // Copy runtime code parts
        uint256 offset = prefixBytes.length + beaconBytes.length;
        for (uint256 i = 0; i < runtimeCode1.length && i + offset < initCode.length; i++) {
            runtimeCode1[i] = initCode[i + offset];
        }
        
        offset += runtimeCode1.length;
        for (uint256 i = 0; i < runtimeCode2.length && i + offset < initCode.length; i++) {
            runtimeCode2[i] = initCode[i + offset];
        }
        
        offset += runtimeCode2.length;
        for (uint256 i = 0; i < runtimeCode3.length && i + offset < initCode.length; i++) {
            runtimeCode3[i] = initCode[i + offset];
        }
        
        // Copy args
        offset += runtimeCode3.length;
        for (uint256 i = 0; i < argsBytes.length && i + offset < initCode.length; i++) {
            argsBytes[i] = initCode[i + offset];
        }
    }
    
    function printInitCodeBreakdown(
        address beacon,
        address foundation,
        address owner
    ) external view {
        (
            bytes memory initCode,
            bytes32 initCodeHash,
            bytes memory prefixBytes,
            bytes memory beaconBytes,
            bytes memory runtimeCode1,
            bytes memory runtimeCode2,
            bytes memory runtimeCode3,
            bytes memory argsBytes
        ) = inspectBeaconProxyInitCode(beacon, foundation, owner);
        
        console.log("=== INIT CODE BREAKDOWN ===");
        console.log("Full init code length:", initCode.length);
        console.log("Init code hash:", vm.toString(initCodeHash));
        console.log("");
        
        console.log("=== PREFIX BYTES (first 82 bytes) ===");
        console.logBytes(prefixBytes);
        console.log("");
        
        console.log("=== BEACON ADDRESS (next 20 bytes) ===");
        console.logBytes(beaconBytes);
        console.log("Beacon address:", beacon);
        console.log("");
        
        console.log("=== RUNTIME CODE PART 1 (32 bytes) ===");
        console.logBytes(runtimeCode1);
        console.log("");
        
        console.log("=== RUNTIME CODE PART 2 (32 bytes) ===");
        console.logBytes(runtimeCode2);
        console.log("");
        
        console.log("=== RUNTIME CODE PART 3 (32 bytes) ===");
        console.logBytes(runtimeCode3);
        console.log("");
        
        console.log("=== ARGS BYTES ===");
        console.logBytes(argsBytes);
        console.log("Args length:", argsBytes.length);
        console.log("");
        
        console.log("=== FULL INIT CODE (hex) ===");
        console.logBytes(initCode);
        console.log("");
        
        console.log("=== EXPECTED HASH ===");
        console.log("Expected: 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247");
        console.log("Actual:   ", vm.toString(initCodeHash));
        console.log("Match:", initCodeHash == 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247);
    }
}
