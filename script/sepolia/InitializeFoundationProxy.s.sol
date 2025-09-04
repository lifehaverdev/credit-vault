// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Foundation} from "src/Foundation.sol";

/// @notice Calls initialize on an already-deployed Foundation proxy.
///         Broadcast with PROXY_DEPLOYER (the proxy admin) or any wallet permitted by the contract.
///         Env vars: PROXY_ADDRESS, OWNER_NFT, OWNER_TOKEN_ID
contract InitializeFoundationProxy is Script {
    function run() external {
        address payable proxy = payable(vm.envAddress("PROXY_ADDRESS"));
        address ownerNFT = vm.envAddress("OWNER_NFT");
        uint256 ownerTokenId = vm.envUint("OWNER_TOKEN_ID");

        vm.startBroadcast();
        Foundation(proxy).initialize(ownerNFT, ownerTokenId);
        console.log("Proxy initialized at:", proxy);
        vm.stopBroadcast();
    }
}
