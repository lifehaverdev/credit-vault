// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract MemoryLayoutAnalyzer is Script {
    function run() external view {
        // Use the exact same values from the user's JavaScript implementation
        address FOUNDATION_ADDRESS = 0x01152530028bd834EDbA9744885A882D025D84F6;
        address CHARTER_BEACON_ADDRESS = 0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C;
        address OWNER_ADDRESS = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
        
        analyzeMemoryLayout(CHARTER_BEACON_ADDRESS, FOUNDATION_ADDRESS, OWNER_ADDRESS);
    }
    
    function analyzeMemoryLayout(
        address beacon,
        address foundation,
        address owner
    ) public view returns (
        bytes32 prefixWord,
        bytes32 beaconWord,
        bytes32 runtimeWord1,
        bytes32 runtimeWord2,
        bytes32 runtimeWord3,
        bytes memory argsLayout
    ) {
        // Encode args exactly like Foundation.computeCharterAddress
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955), // initialize selector
            foundation,
            owner
        );
        
        // Generate init code using LibClone
        bytes memory initCode = LibClone.initCodeERC1967BeaconProxy(beacon, args);
        
        // Extract memory layout components
        // Based on the LibClone implementation, the structure is:
        // [0x00-0x08]: Length prefix
        // [0x09-0x1c]: Beacon address + prefix
        // [0x1d-0x3c]: Runtime code part 1
        // [0x3d-0x5c]: Runtime code part 2
        // [0x5d-0x7c]: Runtime code part 3
        // [0x7d+]: Args
        
        assembly {
            // Extract prefix word (first 32 bytes)
            prefixWord := mload(add(initCode, 0x20))
            
            // Extract beacon word (beacon address + surrounding bytes)
            beaconWord := mload(add(initCode, 0x29)) // 0x20 + 0x09
            
            // Extract runtime code words
            runtimeWord1 := mload(add(initCode, 0x3d)) // 0x20 + 0x1d
            runtimeWord2 := mload(add(initCode, 0x5d)) // 0x20 + 0x3d
            runtimeWord3 := mload(add(initCode, 0x7d)) // 0x20 + 0x5d
        }
        
        // Extract args layout
        argsLayout = new bytes(args.length);
        for (uint256 i = 0; i < args.length; i++) {
            argsLayout[i] = initCode[0x7d + i]; // Start after runtime code
        }
        
        printMemoryLayout(
            initCode,
            prefixWord,
            beaconWord,
            runtimeWord1,
            runtimeWord2,
            runtimeWord3,
            argsLayout,
            beacon,
            foundation,
            owner
        );
    }
    
    function printMemoryLayout(
        bytes memory initCode,
        bytes32 prefixWord,
        bytes32 beaconWord,
        bytes32 runtimeWord1,
        bytes32 runtimeWord2,
        bytes32 runtimeWord3,
        bytes memory argsLayout,
        address beacon,
        address foundation,
        address owner
    ) internal view {
        console.log("=== MEMORY LAYOUT ANALYSIS ===");
        console.log("Total init code length:", initCode.length);
        console.log("");
        
        console.log("=== INPUT PARAMETERS ===");
        console.log("Beacon address:", beacon);
        console.log("Foundation address:", foundation);
        console.log("Owner address:", owner);
        console.log("");
        
        console.log("=== MEMORY WORDS ===");
        console.log("Prefix word (0x00-0x1f):", vm.toString(prefixWord));
        console.log("Beacon word (0x09-0x28):", vm.toString(beaconWord));
        console.log("Runtime word 1 (0x1d-0x3c):", vm.toString(runtimeWord1));
        console.log("Runtime word 2 (0x3d-0x5c):", vm.toString(runtimeWord2));
        console.log("Runtime word 3 (0x5d-0x7c):", vm.toString(runtimeWord3));
        console.log("");
        
        console.log("=== BEACON ADDRESS EXTRACTION ===");
        // Extract beacon address from the beacon word
        address extractedBeacon = address(uint160(uint256(beaconWord) >> 96));
        console.log("Extracted beacon:", extractedBeacon);
        console.log("Expected beacon:", beacon);
        console.log("Match:", extractedBeacon == beacon);
        console.log("");
        
        console.log("=== ARGS LAYOUT ===");
        console.log("Args length:", argsLayout.length);
        console.logBytes(argsLayout);
        console.log("");
        
        console.log("=== BYTE-BY-BYTE BREAKDOWN ===");
        for (uint256 i = 0; i < initCode.length; i++) {
            if (i % 16 == 0) {
                console.log("");
                console.log("Offset 0x%04x:", i);
            }
            console.log("  [%d]: 0x%02x", i, uint8(initCode[i]));
        }
        console.log("");
        
        console.log("=== FINAL HASH ===");
        bytes32 hash = keccak256(initCode);
        console.log("Init code hash:", vm.toString(hash));
        console.log("Expected hash: 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247");
        console.log("Match:", hash == 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247);
    }
    
    function analyzeYulAssembly() external pure {
        console.log("=== YUL ASSEMBLY ANALYSIS ===");
        console.log("Based on LibClone.initCodeERC1967BeaconProxy implementation:");
        console.log("");
        console.log("The Yul assembly does the following:");
        console.log("1. Allocates memory starting at free memory pointer");
        console.log("2. Stores runtime code in three 32-byte chunks");
        console.log("3. Stores beacon address at offset 0x09");
        console.log("4. Stores args at the end");
        console.log("5. Calculates total length and stores at beginning");
        console.log("");
        console.log("Key memory operations:");
        console.log("- mstore(add(c, 0x6b), runtime_code_1)");
        console.log("- mstore(add(c, 0x4b), runtime_code_2)");
        console.log("- mstore(add(c, 0x2b), runtime_code_3)");
        console.log("- mstore(add(c, 0x09), beacon_address)");
        console.log("- Copy args to end of init code");
    }
}
