// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";

contract DumpInitCodeScript is Script {
    /// @notice Get the exact init-code bytes that Solady's LibClone builds for beacon proxy
    /// @param beacon The beacon contract address
    /// @param args The initialization arguments
    /// @return initCode The complete init-code bytes
    /// @return hash The keccak256 hash of the init-code
    function getBeaconProxyInitCode(address beacon, bytes memory args)
        public
        pure
        returns (bytes memory initCode, bytes32 hash)
    {
        // Re-emit the exact init-code bytes Solady builds.
        uint256 n = args.length;
        initCode = new bytes(0x16 + n + 0x75);
        assembly {
            let m := add(initCode, 0x20)        // skip length slot
            // Copy args into memory just like LibClone.
            for { let i := 0 } lt(i, n) { i := add(i, 0x20) } {
                mstore(add(add(m, 0x8b), i), mload(add(add(args, 0x20), i)))
            }
            mstore(add(m, 0x6b), 0xb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3)
            mstore(add(m, 0x4b), 0x1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c)
            mstore(add(m, 0x2b), 0x60195155f3363d3d373d3d363d602036600436635c60da)
            mstore(add(m, 0x14), beacon)
            mstore(m,      add(0x6100523d8160233d3973, shl(56, n)))
            hash := keccak256(add(m, 0x16), add(n, 0x75))
        }
    }

    function run() public pure {
        // Hard-coded addresses matching the JS test
        address beacon = 0x01152530028bd834EDbA9744885A882D025D84F6;  // foundation
        address owner = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;   // owner
        
        // Encode the initialization arguments
        bytes memory args = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            beacon,  // foundation
            owner    // owner
        );
        
        // Get the init code from the debug helper
        (bytes memory initCode, bytes32 initCodeHash) = getBeaconProxyInitCode(beacon, args);
        
        // Log the results
        console2.logBytes(initCode);
        console2.logBytes32(initCodeHash);
        
        // Verify expected properties
        require(initCode.length == 207, "initCode.length != 207");
        
        // Verify hash matches keccak of initCode[0x16:]
        bytes32 expectedHash;
        assembly {
            expectedHash := keccak256(add(initCode, 0x36), sub(mload(initCode), 0x16))
        }
        require(initCodeHash == expectedHash, "initCodeHash mismatch");
    }
}
