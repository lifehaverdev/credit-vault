// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Foundation} from "src/Foundation.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";

contract DeployProxy is Script {
    
    function run() external {
        address ownerNFT = vm.envAddress("OWNER_NFT");
        uint256 ownerTokenId = vm.envUint("OWNER_TOKEN_ID");
        address charterBeacon = vm.envAddress("CHARTER_BEACON");
        
        vm.startBroadcast();

        // Deploy the implementation
        Foundation implementation = new Foundation();
        console.log("Deployed implementation to:", address(implementation));

        // Deploy the proxy using the factory
        address proxy = new ERC1967Factory().deploy(
            address(implementation),
            msg.sender // Initial owner
        );
        console.log("Deployed proxy to:", proxy);

        // Initialize the proxy
        Foundation(payable(proxy)).initialize(ownerNFT, ownerTokenId, charterBeacon);
        console.log("Proxy initialized.");

        vm.stopBroadcast();
    }
}
