// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";
import {CharteredFundImplementation} from "src/CharteredFundImplementation.sol";

/// @notice Deploys a new Foundation implementation and upgrades the UUPS proxy.
///
/// The caller must be the owner (holder of the owner NFT).
///
/// Environment variables:
///   FOUNDATION_PROXY  – address of the live Foundation proxy
///
/// Usage:
///   forge script script/utils/upgrade.s.sol \
///     --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
contract UpgradeFoundation is Script {
    function run() external {
        address proxy = vm.envAddress("FOUNDATION_PROXY");

        vm.startBroadcast();

        // 1. Deploy new implementation
        address newImpl = address(new Foundation());
        console2.log("New Foundation implementation:", newImpl);

        // 2. Upgrade the UUPS proxy. This calls through to _authorizeUpgrade
        //    which is gated onlyOwner. The broadcaster must be the NFT owner.
        Foundation(payable(proxy)).upgradeToAndCall(newImpl, "");

        console2.log("Foundation proxy upgraded:", proxy, "-> impl:", newImpl);

        vm.stopBroadcast();
    }
}
