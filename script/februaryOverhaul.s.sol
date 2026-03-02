// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Foundation} from "src/Foundation.sol";
import {CharteredFundImplementation} from "src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";

/// @notice February 2025 overhaul — runs in a single broadcaster session:
///
///   1. Transfer beacon ownership from admin EOA → Foundation proxy
///   2. Deploy new Foundation implementation (fixes _allocate/_remit bugs,
///      adds creditProtocolEscrow and recoverProtocolOwned)
///   3. Upgrade Foundation UUPS proxy
///   4. Deploy new CharteredFundImplementation (wires up sweepProtocolFees)
///   5. Upgrade the shared charter beacon via Foundation
///   6. Recover ETH protocolOwned corrupted by pre-fix bugs
///   7. Recover ERC20 protocolOwned corrupted by pre-fix bugs
///
/// The broadcaster must be the admin EOA (current beacon owner and NFT holder).
///
/// Recovery amounts are derived from auditProtocolOwned.sh output:
///   ETH:   27100000000000000 wei  (0.0271 ETH — sum of all Donation events)
///   ERC20: 210000000000 wei       (0x98ed... token — partial corruption)
///
/// Usage (dry-run):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/februaryOverhaul.s.sol \
///     --fork-url $RPC_URL --account <keystore-name> -vvvv
///
/// Usage (broadcast):
///   FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///     forge script script/februaryOverhaul.s.sol \
///     --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
contract FebruaryOverhaul is Script {

    // ── Hardcoded recovery amounts from auditProtocolOwned.sh ─────────────────
    // Re-run the audit script before broadcasting to confirm these are still correct.
    uint128 constant ETH_RECOVERY  = 27_100_000_000_000_000; // 0.0271 ETH
    address constant ERC20_TOKEN   = 0x98Ed411B8cf8536657c660Db8aA55D9D4bAAf820;
    uint128 constant ERC20_RECOVERY = 210_000_000_000;

    function run() external {
        address proxy  = vm.envAddress("FOUNDATION_PROXY");
        Foundation hub = Foundation(payable(proxy));

        // ── Pre-flight checks ─────────────────────────────────────────────────
        address beacon      = hub.charterBeacon();
        address beaconOwner = UpgradeableBeacon(beacon).owner();

        console2.log("=== February Overhaul Pre-flight ===");
        console2.log("Foundation proxy:  ", proxy);
        console2.log("Charter beacon:    ", beacon);
        console2.log("Beacon owner (now):", beaconOwner);
        console2.log("Foundation impl:   ", _getImpl(proxy));
        console2.log("Charter impl:      ", UpgradeableBeacon(beacon).implementation());

        // Verify contract has enough ETH to back the ETH recovery amount.
        // protocolOwned represents donations already in the contract — the ETH
        // is physically present, we are only restoring the accounting. If the
        // contract balance is somehow less than the recovery amount something
        // is seriously wrong and we must abort.
        require(
            proxy.balance >= ETH_RECOVERY,
            "Foundation ETH balance less than ETH recovery amount - abort"
        );

        console2.log("Foundation ETH balance:", proxy.balance);
        console2.log("ETH recovery amount:   ", uint256(ETH_RECOVERY));
        console2.log("Pre-flight: OK");
        console2.log("");

        // ── Execute ───────────────────────────────────────────────────────────
        // msg.sender is the broadcaster (keystore account) inside this block.
        vm.startBroadcast();

        // Broadcaster must be the beacon owner — checked here where msg.sender
        // is the actual keystore account rather than the script contract.
        require(
            beaconOwner == msg.sender,
            "Broadcaster is not the beacon owner - cannot transfer beacon"
        );

        // 1. Transfer beacon ownership from admin EOA to Foundation proxy.
        //    After this, Foundation is the sole authority over charter upgrades.
        UpgradeableBeacon(beacon).transferOwnership(proxy);
        console2.log("1. Beacon ownership transferred to Foundation");

        // 2. Deploy new Foundation implementation.
        address newFoundationImpl = address(new Foundation());
        console2.log("2. New Foundation impl deployed:", newFoundationImpl);

        // 3. Upgrade Foundation UUPS proxy.
        //    Calls through to _authorizeUpgrade which is gated onlyOwner.
        hub.upgradeToAndCall(newFoundationImpl, "");
        console2.log("3. Foundation proxy upgraded");

        // 4. Deploy new CharteredFundImplementation.
        address newCharterImpl = address(new CharteredFundImplementation());
        console2.log("4. New CharteredFundImplementation deployed:", newCharterImpl);

        // 5. Upgrade the charter beacon via Foundation.
        //    All chartered fund proxies immediately point to the new implementation.
        hub.upgradeCharterImplementation(newCharterImpl);
        console2.log("5. Charter beacon upgraded - all vaults now on new impl");

        // 6. Recover ETH protocolOwned.
        //    The ETH is already in the contract; this restores the accounting slot
        //    that was zeroed by the pre-fix _allocate/_remit bugs.
        hub.recoverProtocolOwned(address(0), ETH_RECOVERY);
        console2.log("6. ETH protocolOwned restored:", uint256(ETH_RECOVERY));

        // 7. Recover ERC20 protocolOwned.
        hub.recoverProtocolOwned(ERC20_TOKEN, ERC20_RECOVERY);
        console2.log("7. ERC20 protocolOwned restored:", uint256(ERC20_RECOVERY));

        vm.stopBroadcast();

        // ── Post-flight verification ──────────────────────────────────────────
        console2.log("");
        console2.log("=== Post-flight Verification ===");

        address newBeaconOwner = UpgradeableBeacon(beacon).owner();
        address liveFoundationImpl = _getImpl(proxy);
        address liveCharterImpl = UpgradeableBeacon(beacon).implementation();

        console2.log("Beacon owner:        ", newBeaconOwner);
        console2.log("Foundation impl:     ", liveFoundationImpl);
        console2.log("Charter impl:        ", liveCharterImpl);

        // Read restored custody slots
        bytes32 ethKey = keccak256(abi.encodePacked(proxy, address(0)));
        bytes32 ethSlot = hub.custody(ethKey);
        uint128 ethOwned  = uint128(uint256(ethSlot));
        uint128 ethEscrow = uint128(uint256(ethSlot >> 128));
        console2.log("ETH protocolOwned:   ", uint256(ethOwned));
        console2.log("ETH protocolEscrow:  ", uint256(ethEscrow));

        bytes32 erc20Key = keccak256(abi.encodePacked(proxy, ERC20_TOKEN));
        bytes32 erc20Slot = hub.custody(erc20Key);
        uint128 erc20Owned  = uint128(uint256(erc20Slot));
        console2.log("ERC20 protocolOwned: ", uint256(erc20Owned));

        // Sanity: after recovery, protocolOwned must not exceed contract balance
        require(
            ethOwned <= proxy.balance,
            "Post-recovery: ETH protocolOwned exceeds contract balance - critical"
        );

        require(newBeaconOwner == proxy,      "Beacon owner not set to Foundation");
        require(liveFoundationImpl != address(0), "Foundation impl is zero");
        require(liveCharterImpl    != address(0), "Charter impl is zero");
        require(ethOwned == ETH_RECOVERY,     "ETH recovery amount mismatch");
        require(erc20Owned >= ERC20_RECOVERY, "ERC20 recovery amount mismatch");

        console2.log("Post-flight: ALL CHECKS PASSED");
    }

    function _getImpl(address proxy) internal view returns (address) {
        // ERC1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(proxy, slot))));
    }
}
