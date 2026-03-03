// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";

/// @notice March 2025 overhaul — single-transaction upgrade:
///
///   1. Deploy new Foundation implementation
///      - Fixes Foundation.commit fee bug: previously `_packAmount(0, escrow+fee)`
///        silently zeroed `protocolOwned` whenever a commit fee was charged.
///        Fixed to `_packAmount(owned, escrow+fee)`, preserving the owned slot.
///
///   2. Upgrade Foundation UUPS proxy to the new implementation
///
/// No CharteredFundImplementation change required — the charter beacon
/// already runs the correct implementation from the February overhaul.
///
/// NOTE: Run auditProtocolOwned.sh before broadcasting to check whether any
/// protocolOwned was corrupted between the February and March upgrades.
/// If commits with fee > 0 were issued against the root vault in that window,
/// a recoverProtocolOwned call should be appended here.
///
/// Usage (dry-run):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/marchOverhaul.s.sol \
///     --fork-url $RPC_URL --account <keystore-name> -vvvv
///
/// Usage (broadcast):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/marchOverhaul.s.sol \
///     --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
contract MarchOverhaul is Script {

    function run() external {
        address proxy  = vm.envAddress("FOUNDATION_PROXY");
        Foundation hub = Foundation(payable(proxy));

        // ── Pre-flight ────────────────────────────────────────────────────
        console2.log("=== March Overhaul Pre-flight ===");
        console2.log("Foundation proxy:    ", proxy);
        console2.log("Current impl:        ", _getImpl(proxy));

        // Snapshot protocolOwned before upgrade to detect any window corruption.
        bytes32 ethKey = keccak256(abi.encodePacked(proxy, address(0)));
        bytes32 ethSlot = hub.custody(ethKey);
        uint128 ethOwnedBefore  = uint128(uint256(ethSlot));
        uint128 ethEscrowBefore = uint128(uint256(ethSlot >> 128));
        console2.log("ETH protocolOwned (pre):  ", uint256(ethOwnedBefore));
        console2.log("ETH protocolEscrow (pre): ", uint256(ethEscrowBefore));
        console2.log("Pre-flight: OK");
        console2.log("");

        // ── Execute ───────────────────────────────────────────────────────
        vm.startBroadcast();

        // 1. Deploy new Foundation implementation with the commit fee fix.
        address newImpl = address(new Foundation());
        console2.log("1. New Foundation impl deployed:", newImpl);

        // 2. Upgrade the UUPS proxy.
        //    _authorizeUpgrade is gated onlyOwner (NFT holder = broadcaster).
        hub.upgradeToAndCall(newImpl, "");
        console2.log("2. Foundation proxy upgraded");

        vm.stopBroadcast();

        // ── Post-flight ───────────────────────────────────────────────────
        console2.log("");
        console2.log("=== March Overhaul Post-flight ===");

        address liveImpl = _getImpl(proxy);
        console2.log("Foundation impl (live): ", liveImpl);

        bytes32 ethSlotAfter = hub.custody(ethKey);
        uint128 ethOwnedAfter  = uint128(uint256(ethSlotAfter));
        uint128 ethEscrowAfter = uint128(uint256(ethSlotAfter >> 128));
        console2.log("ETH protocolOwned (post):  ", uint256(ethOwnedAfter));
        console2.log("ETH protocolEscrow (post): ", uint256(ethEscrowAfter));

        require(liveImpl == newImpl,                   "Impl mismatch - upgrade failed");
        require(ethOwnedAfter  == ethOwnedBefore,      "protocolOwned changed during upgrade - investigate");
        require(ethEscrowAfter == ethEscrowBefore,     "protocolEscrow changed during upgrade - investigate");

        console2.log("Post-flight: ALL CHECKS PASSED");
    }

    function _getImpl(address proxy) internal view returns (address) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(proxy, slot))));
    }
}
