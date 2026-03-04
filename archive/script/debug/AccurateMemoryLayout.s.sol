// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract AccurateMemoryLayout is Script {
    function run() external view {
        // Use the exact same values from the user's JavaScript implementation
        address FOUNDATION_ADDRESS = 0x01152530028bd834EDbA9744885A882D025D84F6;
        address CHARTER_BEACON_ADDRESS = 0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C;
        address OWNER_ADDRESS = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
        
        analyzeAccurateMemoryLayout(CHARTER_BEACON_ADDRESS, FOUNDATION_ADDRESS, OWNER_ADDRESS);
    }
    
    function analyzeAccurateMemoryLayout(
        address beacon,
        address foundation,
        address owner
    ) public view {
        // Encode args exactly like Foundation.computeCharterAddress
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955), // initialize selector
            foundation,
            owner
        );
        
        console.log("=== ACCURATE MEMORY LAYOUT ANALYSIS ===");
        console.log("Beacon address:", beacon);
        console.log("Foundation address:", foundation);
        console.log("Owner address:", owner);
        console.log("Args length:", args.length);
        console.log("");
        
        // Generate init code using LibClone
        bytes memory initCode = LibClone.initCodeERC1967BeaconProxy(beacon, args);
        bytes32 initCodeHash = keccak256(initCode);
        
        console.log("=== INIT CODE GENERATION ===");
        console.log("Init code length:", initCode.length);
        console.log("Init code hash:", vm.toString(initCodeHash));
        console.log("");
        
        // Now let's manually recreate the hash calculation from LibClone
        bytes32 manualHash = calculateHashManually(beacon, args);
        console.log("=== MANUAL HASH CALCULATION ===");
        console.log("Manual hash:", vm.toString(manualHash));
        console.log("LibClone hash:", vm.toString(initCodeHash));
        console.log("Match:", manualHash == initCodeHash);
        console.log("");
        
        // Compare with expected values
        console.log("=== COMPARISON WITH EXPECTED VALUES ===");
        bytes32 expectedHash = 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247;
        bytes32 userHash = 0xa1aa07c9cc88d386a06e47b4afce696ba67087b8e79cb42f0d4bab09d253ab6e;
        
        console.log("Expected hash: ", vm.toString(expectedHash));
        console.log("Actual hash:   ", vm.toString(initCodeHash));
        console.log("User hash:     ", vm.toString(userHash));
        console.log("");
        console.log("Expected match:", initCodeHash == expectedHash);
        console.log("User match:    ", initCodeHash == userHash);
        
        // Print the exact memory layout that gets hashed
        printMemoryLayoutForHashing(beacon, args);
    }
    
    function calculateHashManually(address beacon, bytes memory args) internal pure returns (bytes32 hash) {
        assembly {
            let m := mload(0x40)
            let n := mload(args)
            
            // Copy args to offset 0x8b
            for { let i := 0 } lt(i, n) { i := add(i, 0x20) } {
                mstore(add(add(m, 0x8b), i), mload(add(add(args, 0x20), i)))
            }
            
            // Store runtime code parts
            mstore(add(m, 0x6b), 0xb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3)
            mstore(add(m, 0x4b), 0x1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c)
            mstore(add(m, 0x2b), 0x60195155f3363d3d373d3d363d602036600436635c60da)
            
            // Store beacon at offset 0x14
            mstore(add(m, 0x14), beacon)
            
            // Store prefix at offset 0x00
            mstore(m, add(0x6100523d8160233d3973, shl(56, n)))
            
            // Calculate hash from offset 0x16 with length n + 0x75
            hash := keccak256(add(m, 0x16), add(n, 0x75))
        }
    }
    
    function printMemoryLayoutForHashing(address beacon, bytes memory args) internal view {
        console.log("=== MEMORY LAYOUT FOR HASHING ===");
        console.log("This shows the exact memory layout that gets hashed by LibClone");
        console.log("");
        
        // Create the memory layout manually
        bytes memory memoryLayout = createMemoryLayout(beacon, args);
        
        console.log("Memory layout length:", memoryLayout.length);
        console.log("Memory layout (hex):");
        console.logBytes(memoryLayout);
        console.log("");
        
        // Show the hash calculation
        bytes32 hash = keccak256(memoryLayout);
        console.log("Hash of memory layout:", vm.toString(hash));
        
        // Show byte-by-byte breakdown
        console.log("=== BYTE-BY-BYTE BREAKDOWN ===");
        for (uint256 i = 0; i < memoryLayout.length; i++) {
            if (i % 32 == 0) {
                console.log("");
                console.log("Offset 0x%04x:", i);
            }
            console.log("  [%d]: 0x%02x", i, uint8(memoryLayout[i]));
        }
    }
    
    function createMemoryLayout(address beacon, bytes memory args) internal pure returns (bytes memory) {
        // This recreates the exact memory layout that LibClone uses for hashing
        // The hash is calculated from offset 0x16 with length n + 0x75
        
        uint256 n = args.length;
        uint256 totalLength = n + 0x75;
        bytes memory layout = new bytes(totalLength);
        
        assembly {
            let ptr := add(layout, 0x20)
            
            // Copy args to offset 0x8b - 0x16 = 0x75
            for { let i := 0 } lt(i, n) { i := add(i, 0x20) } {
                mstore(add(ptr, add(0x75, i)), mload(add(add(args, 0x20), i)))
            }
            
            // Store runtime code parts at relative offsets
            mstore(add(ptr, 0x55), 0xb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3)
            mstore(add(ptr, 0x35), 0x1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c)
            mstore(add(ptr, 0x15), 0x60195155f3363d3d373d3d363d602036600436635c60da)
            
            // Store beacon at relative offset 0x14 - 0x16 = -0x02 (wraps around)
            // Actually, the beacon is stored at offset 0x14 in the full layout,
            // but we're starting from offset 0x16, so we need to adjust
            mstore(add(ptr, sub(0x14, 0x16)), beacon)
            
            // Store prefix at relative offset 0x00 - 0x16 = -0x16 (wraps around)
            mstore(add(ptr, sub(0x00, 0x16)), add(0x6100523d8160233d3973, shl(56, n)))
        }
        
        return layout;
    }
}


