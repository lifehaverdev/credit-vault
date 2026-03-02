// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";
import {CharteredFundImplementation} from "src/CharteredFundImplementation.sol";

/// @notice Deploys a new CharteredFundImplementation and upgrades the beacon via Foundation.
///
/// All existing chartered fund proxies will immediately point to the new implementation.
/// The caller must be the owner (holder of the owner NFT).
///
/// Environment variables:
///   FOUNDATION_PROXY  – address of the live Foundation proxy
///
/// Usage:
///   forge script script/utils/upgradeCharter.s.sol \
///     --fork-url $RPC_URL --broadcast --sender $OWNER_WALLET -vvvv
contract UpgradeCharter is Script {
    function run() external {
        address proxy = vm.envAddress("FOUNDATION_PROXY");

        vm.startBroadcast();

        // 1. Deploy new CharteredFundImplementation
        address newImpl = address(new CharteredFundImplementation());
        console2.log("New CharteredFundImplementation:", newImpl);

        // 2. Upgrade via Foundation (gated onlyOwner, updates the shared beacon)
        Foundation(payable(proxy)).upgradeCharterImplementation(newImpl);

        console2.log("Charter beacon upgraded to:", newImpl);

        vm.stopBroadcast();
    }
}
