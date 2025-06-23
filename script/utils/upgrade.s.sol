// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Factory address (same as deployment)
address constant FACTORY = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24;
// The proxy we want to upgrade
address payable constant PROXY = payable(0x011528b1d5822B3269d919e38872cC33bdec6d17);
// The new implementation contract
address payable constant NEW_IMPLEMENTATION = payable(0x115255EE8bD792f659944f37D641254d9bf05d3C);

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
            PROXY,
            NEW_IMPLEMENTATION,
            initCalldata
        );

        console.log("Proxy at", PROXY, "upgraded to new implementation at", NEW_IMPLEMENTATION);

        vm.stopBroadcast();
    }
} 