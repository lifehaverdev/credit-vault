// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "createx-forge/src/ERC1967Proxy.sol";
import {Foundation} from "src/Foundation.sol";

/// @notice Deploys the ERC1967 proxy at nonce-0 from the PROXY_DEPLOYER key.
///         Expects the implementation address to be provided via $IMPL_ADDRESS.
///         After deployment it calls initialize(ownerNFT, ownerTokenId).
contract DeployFoundationProxy is Script {
    function run() external {
        // ---------------------------------------------------------------------
        // Load ENV
        // ---------------------------------------------------------------------
        address impl = vm.envAddress("IMPL_ADDRESS");
        address ownerNFT = vm.envAddress("OWNER_NFT");
        uint256 ownerTokenId = vm.envUint("OWNER_TOKEN_ID");

        // ---------------------------------------------------------------------
        // Broadcast transaction (must be nonce-0!)
        // ---------------------------------------------------------------------
        vm.startBroadcast();

        // Deploy proxy.  Constructor calldata is empty – we initialise afterwards.
        ERC1967Proxy proxy = new ERC1967Proxy(impl, "");
        address proxyAddr = address(proxy);
        console.log("Proxy deployed to:", proxyAddr);

        // Initialise the proxy
        Foundation(payable(proxyAddr)).initialize(ownerNFT, ownerTokenId);
        console.log("Proxy initialised.");

        vm.stopBroadcast();
    }
}
