// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";

/// @notice May 2025 Foundation upgrade — adds withdrawProtocolOwned.
///
///   Background
///   ----------
///   Foundation.custody[Foundation][token].owned accumulates from:
///     • ETH/ERC20 donations (via _donate)
///     • recoverProtocolOwned accounting corrections (March 2025)
///   But no extraction path existed — those funds were permanently locked.
///
///   This upgrade adds:
///     withdrawProtocolOwned(address token, uint256 amount) onlyOwner
///     Decrements protocolOwned and transfers ETH/ERC20 to the owner wallet.
///
///   No beacon changes — only the Foundation UUPS implementation is replaced.
///   No proxy address changes.
///
/// Usage (dry-run):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/mayOverhaul.s.sol \
///     --fork-url $RPC_URL --sender $ADMIN -vvvv
///
/// Usage (broadcast):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/mayOverhaul.s.sol \
///     --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
contract MayOverhaul is Script {

    function run() external {
        address proxy = vm.envAddress("FOUNDATION_PROXY");
        Foundation hub = Foundation(payable(proxy));

        // -- Pre-flight --------------------------------------------------
        console2.log("=== May Overhaul Pre-flight ===");
        console2.log("Foundation proxy:     ", proxy);
        console2.log("Charter beacon:       ", hub.charterBeacon());

        address oldImpl = _getImpl(proxy);
        console2.log("Current Foundation impl:", oldImpl);

        require(oldImpl != address(0), "Could not read current impl");
        console2.log("Pre-flight: OK");
        console2.log("");

        // -- Execute -----------------------------------------------------
        vm.startBroadcast();

        // Deploy new Foundation implementation with withdrawProtocolOwned.
        address newImpl = address(new Foundation());
        console2.log("1. New Foundation implementation deployed:", newImpl);

        // Upgrade UUPS proxy. onlyOwner = NFT holder = broadcaster.
        hub.upgradeToAndCall(newImpl, "");
        console2.log("2. Foundation proxy upgraded to new implementation");

        vm.stopBroadcast();

        // -- Post-flight -------------------------------------------------
        console2.log("");
        console2.log("=== May Overhaul Post-flight ===");

        address liveImpl = _getImpl(proxy);
        console2.log("Foundation impl (live):", liveImpl);

        require(liveImpl == newImpl, "Foundation impl mismatch - upgrade failed");
        console2.log("Post-flight: ALL CHECKS PASSED");
    }

    /// @dev Reads the ERC1967 implementation slot.
    function _getImpl(address proxy) internal view returns (address impl) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 val;
        assembly { val := sload(slot) }
        // sload on an external address via staticcall — use vm.load instead
        val = vm.load(proxy, slot);
        impl = address(uint160(uint256(val)));
    }
}
