// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title DebugCloneHelper
/// @notice Helper contract to retrieve the exact init-code that Solady's LibClone builds
///         for beacon proxy initialization. Used for debugging and verification.
contract DebugCloneHelper {
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
}
