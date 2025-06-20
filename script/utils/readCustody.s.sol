// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultRoot} from "src/VaultRoot.sol";

// The address of the proxied VaultRoot contract
address constant VAULT_ROOT_PROXY = 0x011528b1d5822B3269d919e38872cC33bdec6d17;
// The user address to check
address constant USER_ADDRESS = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
// The token address for Ethereum
address constant ETH_ADDRESS = address(0);

contract ReadCustody is Script {

    function _splitAmount(bytes32 amount) internal pure returns(uint128 userOwned, uint128 escrow) {
        userOwned = uint128(uint256(amount));
        escrow = uint128(uint256(amount >> 128));
    }

    function run() external view {
        VaultRoot vaultRoot = VaultRoot(payable(VAULT_ROOT_PROXY));

        // Replicate the _getCustodyKey logic
        bytes32 custodyKey = keccak256(abi.encodePacked(USER_ADDRESS, ETH_ADDRESS));

        // Read the custody value
        bytes32 custodyValue = vaultRoot.custody(custodyKey);

        (uint128 userOwned, uint128 escrow) = _splitAmount(custodyValue);

        console.log("Reading custody for user:", USER_ADDRESS);
        console.log("Token (address(0) is ETH):", ETH_ADDRESS);
        console.log("Proxy Address:", VAULT_ROOT_PROXY);
        console.log("===================================");
        console.log("Custody Key:");
        console.logBytes32(custodyKey);
        console.log("Raw Custody Value:");
        console.logBytes32(custodyValue);
        console.log("User Owned Balance:", userOwned);
        console.log("Escrow Balance:", escrow);
    }
} 