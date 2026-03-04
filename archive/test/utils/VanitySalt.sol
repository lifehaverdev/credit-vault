// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibClone} from "solady/utils/LibClone.sol";

/// @title VanitySalt
/// @notice Helper library for Foundry tests to mine a salt that yields an
///         ERC1967BeaconProxy whose address starts with 0x1152.
/// @dev Uses brute-force search; bounded loop is fine in test context.
library VanitySalt {
    error SaltNotFound();

    /// @param beacon     Address of the UpgradeableBeacon used for the proxy.
    /// @param initCalldata Calldata passed to the proxy constructor (encoded args).
    /// @param deployer   The address that will perform the CREATE2 (the Foundation hub).
    /// @param max        Maximum number of iterations to try (safety valve).
    /// @return salt      The first salt that satisfies the vanity prefix.
    function mine(
        address beacon,
        bytes memory initCalldata,
        address deployer,
        uint256 max
    ) internal pure returns (bytes32 salt) {
        unchecked {
            for (uint256 i; i < max; ++i) {
                salt = bytes32(i);
                address predicted = LibClone.predictDeterministicAddressERC1967BeaconProxy(
                    beacon,
                    initCalldata,
                    salt,
                    deployer
                );
                if (uint160(predicted) >> 144 == 0x1152) {
                    return salt;
                }
            }
        }
        revert SaltNotFound();
    }
}
