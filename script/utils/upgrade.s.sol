// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Factory address (same as deployment)
address constant FACTORY = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24;
// The proxy we want to upgrade
address payable constant FOUNDATION_PROXY = payable(0x011528b1d5822B3269d919e38872cC33bdec6d17);
// The new implementation contract
address payable constant NEW_FOUNDATION_IMPLEMENTATION = payable(0x115230E319CCD1c760D89a8a4059ac4883240526);

interface IERC1967Factory {
    function upgradeAndCall(
        address proxy,
        address implementation,
        bytes calldata data
    ) external payable;
}

contract UpgradeProxy is Script {
    function run() external {
        vm.startBroadcast();

        // We don't need to call any function on the new implementation upon upgrade, so we pass empty calldata.
        bytes memory initCalldata = "";

        IERC1967Factory(FACTORY).upgradeAndCall(
            FOUNDATION_PROXY,
            NEW_FOUNDATION_IMPLEMENTATION,
            initCalldata
        );

        console.log("Proxy at", FOUNDATION_PROXY, "upgraded to new implementation at", NEW_FOUNDATION_IMPLEMENTATION);

        vm.stopBroadcast();
    }
} 