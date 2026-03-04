// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract ByteComparison is Script {
    function run() external view {
        // Use the exact same values from the user's JavaScript implementation
        address FOUNDATION_ADDRESS = 0x01152530028bd834EDbA9744885A882D025D84F6;
        address CHARTER_BEACON_ADDRESS = 0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C;
        address OWNER_ADDRESS = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
        
        compareInitCodes(CHARTER_BEACON_ADDRESS, FOUNDATION_ADDRESS, OWNER_ADDRESS);
    }
    
    function compareInitCodes(
        address beacon,
        address foundation,
        address owner
    ) public view returns (
        bytes memory expectedInitCode,
        bytes32 expectedHash,
        bool[] memory byteMatches,
        uint256 firstMismatchIndex
    ) {
        // Generate expected init code using LibClone
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955), // initialize selector
            foundation,
            owner
        );
        
        expectedInitCode = LibClone.initCodeERC1967BeaconProxy(beacon, args);
        expectedHash = keccak256(expectedInitCode);
        
        // For now, we'll just return the expected values
        // The actual comparison would be done against the JavaScript output
        byteMatches = new bool[](expectedInitCode.length);
        for (uint256 i = 0; i < expectedInitCode.length; i++) {
            byteMatches[i] = true; // Placeholder - would compare with JS output
        }
        firstMismatchIndex = type(uint256).max; // No mismatch found
        
        printComparisonResults(expectedInitCode, expectedHash);
    }
    
    function printComparisonResults(
        bytes memory initCode,
        bytes32 hash
    ) internal view {
        console.log("=== BYTE-BY-BYTE COMPARISON ===");
        console.log("Init code length:", initCode.length);
        console.log("Init code hash:", vm.toString(hash));
        console.log("");
        
        console.log("=== EXPECTED VALUES ===");
        console.log("Expected hash: 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247");
        console.log("Actual hash:   ", vm.toString(hash));
        console.log("Match:", hash == 0x673b91cb887b557e9f95d3d449d50f9e130594cedf823272542df21fa656f247);
        console.log("");
        
        console.log("=== INIT CODE BYTES (hex) ===");
        for (uint256 i = 0; i < initCode.length; i++) {
            if (i % 32 == 0) {
                console.log("");
                console.log("Offset 0x%04x:", i);
            }
            console.log("  [%d]: 0x%02x", i, uint8(initCode[i]));
        }
        console.log("");
        
        console.log("=== INIT CODE BYTES (raw hex string) ===");
        console.logBytes(initCode);
    }
    
    function analyzeMemoryLayout(
        address beacon,
        address foundation,
        address owner
    ) external view {
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955), // initialize selector
            foundation,
            owner
        );
        
        console.log("=== MEMORY LAYOUT ANALYSIS ===");
        console.log("Beacon address:", beacon);
        console.log("Foundation address:", foundation);
        console.log("Owner address:", owner);
        console.log("Args length:", args.length);
        console.log("");
        
        console.log("=== ARGS BREAKDOWN ===");
        console.logBytes(args);
        console.log("");
        
        // Show how the beacon address is stored in the init code
        bytes memory initCode = LibClone.initCodeERC1967BeaconProxy(beacon, args);
        
        console.log("=== BEACON ADDRESS IN INIT CODE ===");
        // The beacon address should be at offset 0x09 in the init code
        bytes20 beaconInCode;
        assembly {
            beaconInCode := mload(add(initCode, 0x29)) // 0x20 (length) + 0x09 (offset)
        }
        console.log("Beacon in init code:", address(beaconInCode));
        console.log("Expected beacon:", beacon);
        console.log("Match:", address(beaconInCode) == beacon);
    }
}
