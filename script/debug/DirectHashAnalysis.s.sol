// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract DirectHashAnalysis is Script {
    function run() external view {
        // Use the exact same values from the user's JavaScript implementation
        address FOUNDATION_ADDRESS = 0x01152530028bd834EDbA9744885A882D025D84F6;
        address CHARTER_BEACON_ADDRESS = 0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C;
        address OWNER_ADDRESS = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
        
        analyzeDirectHash(CHARTER_BEACON_ADDRESS, FOUNDATION_ADDRESS, OWNER_ADDRESS);
    }
    
    function analyzeDirectHash(
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
        
        console.log("=== DIRECT HASH ANALYSIS ===");
        console.log("Beacon address:", beacon);
        console.log("Foundation address:", foundation);
        console.log("Owner address:", owner);
        console.log("Args length:", args.length);
        console.log("");
        
        // Get the hash directly from LibClone
        bytes32 libCloneHash = LibClone.initCodeHashERC1967BeaconProxy(beacon, args);
        console.log("LibClone hash:", vm.toString(libCloneHash));
        
        // Get the init code and hash it manually
        bytes memory initCode = LibClone.initCodeERC1967BeaconProxy(beacon, args);
        bytes32 manualHash = keccak256(initCode);
        console.log("Manual hash:  ", vm.toString(manualHash));
        console.log("Match:", libCloneHash == manualHash);
        console.log("");
        
        // Compare with expected values
        bytes32 expectedHash = 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247;
        bytes32 userHash = 0xa1aa07c9cc88d386a06e47b4afce696ba67087b8e79cb42f0d4bab09d253ab6e;
        
        console.log("=== COMPARISON ===");
        console.log("Expected hash: ", vm.toString(expectedHash));
        console.log("LibClone hash: ", vm.toString(libCloneHash));
        console.log("User hash:     ", vm.toString(userHash));
        console.log("");
        console.log("Expected match:", libCloneHash == expectedHash);
        console.log("User match:    ", libCloneHash == userHash);
        console.log("");
        
        // Print the init code that gets hashed
        console.log("=== INIT CODE THAT GETS HASHED ===");
        console.log("Length:", initCode.length);
        console.logBytes(initCode);
        console.log("");
        
        // Show the exact memory layout that LibClone uses internally
        showLibCloneMemoryLayout(beacon, args);
    }
    
    function showLibCloneMemoryLayout(address beacon, bytes memory args) internal view {
        console.log("=== LIBCLONE INTERNAL MEMORY LAYOUT ===");
        console.log("This shows what LibClone.initCodeHashERC1967BeaconProxy does internally");
        console.log("");
        
        // Recreate the exact memory layout that LibClone uses
        bytes32 hash;
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
        
        console.log("Internal hash:", vm.toString(hash));
        
        // Now let's extract the exact bytes that get hashed
        bytes memory hashedBytes = extractHashedBytes(beacon, args);
        console.log("Hashed bytes length:", hashedBytes.length);
        console.logBytes(hashedBytes);
        console.log("");
        
        // Show byte-by-byte breakdown
        console.log("=== BYTE-BY-BYTE BREAKDOWN OF HASHED BYTES ===");
        for (uint256 i = 0; i < hashedBytes.length; i++) {
            if (i % 32 == 0) {
                console.log("");
                console.log("Offset 0x%04x:", i);
            }
            console.log("  [%d]: 0x%02x", i, uint8(hashedBytes[i]));
        }
    }
    
    function extractHashedBytes(address beacon, bytes memory args) internal pure returns (bytes memory) {
        uint256 n = args.length;
        uint256 length = n + 0x75;
        bytes memory result = new bytes(length);
        
        assembly {
            let m := mload(0x40)
            let resultPtr := add(result, 0x20)
            
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
            
            // Copy the hashed region to result
            for { let i := 0 } lt(i, length) { i := add(i, 0x20) } {
                mstore(add(resultPtr, i), mload(add(add(m, 0x16), i)))
            }
        }
        
        return result;
    }
}


