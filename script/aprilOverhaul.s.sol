// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";
import {CharteredFundImplementation} from "src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";

/// @notice April 2025 charter beacon upgrade - single-transaction, three fixes:
///
///   1. marshalCall(address target, bytes calldata data) external onlyMarshal
///      Marshal-accessible external call relay on CharteredFundImplementation.
///      Replaces the onlyOwner performCalldata path for calls that require the
///      fund as msg.sender (e.g. Foundation.onlyCharteredFund functions).
///
///   2. CharteredFundImplementation.commit fee constraint verified working:
///      commit(escrowAmount == userOwned, charterFee=0, protocolFee=0) passes,
///      enabling the two-step seizure pattern:
///        step 1: commit(user, token, fullBalance, 0, 0, metadata)
///        step 2: remit(user, token, 0, seizureAmount, metadata)
///
///   3. sweepProtocolFees implementation wired to Foundation.creditProtocolEscrow:
///      ETH path: foundation.creditProtocolEscrow{value: amount}(token, amount)
///      ERC20 path: safeTransfer to Foundation, then creditProtocolEscrow(token, amount)
///
/// No Foundation upgrade required - Foundation is already correct post March upgrade.
/// No proxy address changes - only the charter beacon implementation is replaced.
///
/// Usage (dry-run):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/aprilOverhaul.s.sol \
///     --fork-url $RPC_URL --sender $ADMIN -vvvv
///
/// Usage (broadcast):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/aprilOverhaul.s.sol \
///     --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
contract AprilOverhaul is Script {

    function run() external {
        address proxy  = vm.envAddress("FOUNDATION_PROXY");
        Foundation hub = Foundation(payable(proxy));

        address beacon = hub.charterBeacon();

        // -- Pre-flight --------------------------------------------------
        console2.log("=== April Overhaul Pre-flight ===");
        console2.log("Foundation proxy:     ", proxy);
        console2.log("Charter beacon:       ", beacon);
        console2.log("Current charter impl: ", UpgradeableBeacon(beacon).implementation());
        console2.log("Beacon owner:         ", UpgradeableBeacon(beacon).owner());
        require(
            UpgradeableBeacon(beacon).owner() == proxy,
            "Beacon owner is not Foundation - cannot upgrade"
        );
        console2.log("Pre-flight: OK");
        console2.log("");

        // -- Execute -----------------------------------------------------
        vm.startBroadcast();

        // Deploy new CharteredFundImplementation with all three fixes.
        address newCharterImpl = address(new CharteredFundImplementation());
        console2.log("1. New CharteredFundImplementation deployed:", newCharterImpl);

        // Upgrade the beacon via Foundation (onlyOwner = NFT holder = broadcaster).
        // All chartered fund proxies immediately point to the new implementation.
        hub.upgradeCharterImplementation(newCharterImpl);
        console2.log("2. Charter beacon upgraded - all vaults now on new impl");

        vm.stopBroadcast();

        // -- Post-flight -------------------------------------------------
        console2.log("");
        console2.log("=== April Overhaul Post-flight ===");

        address liveImpl = UpgradeableBeacon(beacon).implementation();
        console2.log("Charter impl (live): ", liveImpl);

        require(liveImpl == newCharterImpl, "Charter impl mismatch - upgrade failed");
        console2.log("Post-flight: ALL CHECKS PASSED");
    }
}
