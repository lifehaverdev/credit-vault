// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

/// @notice Drain script for the old Foundation vault (V1).
///
///   Two tokens: ETH and MS2 (0x98Ed411B8cf8536657c660Db8aA55D9D4bAAf820).
///
///   Step 1 — Audit (read-only, no broadcast):
///     FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///       forge script script/DrainFoundation.s.sol:DrainAudit \
///       --fork-url $RPC_URL -vvvv
///
///   Step 2 — Drain (broadcast):
///     FOUNDATION_PROXY=0x01152530028bd834EDbA9744885A882D025D84F6 \
///       forge script script/DrainFoundation.s.sol:DrainExecute \
///       --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv

interface IFoundation {
    function custody(bytes32 key) external view returns (bytes32);
    function withdrawProtocolOwned(address token, uint256 amount) external;
    function performCalldata(address target, bytes calldata data) external payable;
    function ownerNFT() external view returns (address);
    function ownerTokenId() external view returns (uint256);
    function marshalFrozen() external view returns (bool);
    function refund() external view returns (bool);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @notice Read-only audit: prints ETH and MS2 balances held by the Foundation proxy.
contract DrainAudit is Script {
    address constant MS2 = 0x98Ed411B8cf8536657c660Db8aA55D9D4bAAf820;

    function run() external view {
        address proxy = vm.envAddress("FOUNDATION_PROXY");
        IFoundation hub = IFoundation(proxy);

        console2.log("=== Foundation Drain Audit ===");
        console2.log("Proxy:          ", proxy);
        console2.log("Owner NFT:      ", hub.ownerNFT());
        console2.log("Owner Token ID: ", hub.ownerTokenId());
        console2.log("Marshal Frozen: ", hub.marshalFrozen());
        console2.log("Refund Mode:    ", hub.refund());
        console2.log("");

        // --- ETH ---
        uint256 ethBalance = proxy.balance;
        bytes32 ethKey = keccak256(abi.encodePacked(proxy, address(0)));
        bytes32 ethSlot = hub.custody(ethKey);
        (uint128 ethOwned, uint128 ethEscrow) = _split(ethSlot);

        console2.log("=== ETH ===");
        console2.log("  contract balance:", ethBalance);
        console2.log("  custody owned:   ", uint256(ethOwned));
        console2.log("  custody escrow:  ", uint256(ethEscrow));

        uint256 ethAccounted = uint256(ethOwned) + uint256(ethEscrow);
        if (ethBalance > ethAccounted) {
            console2.log("  UNACCOUNTED:     ", ethBalance - ethAccounted);
        }

        // --- MS2 ---
        uint256 ms2Balance = IERC20(MS2).balanceOf(proxy);
        bytes32 ms2Key = keccak256(abi.encodePacked(proxy, MS2));
        bytes32 ms2Slot = hub.custody(ms2Key);
        (uint128 ms2Owned, uint128 ms2Escrow) = _split(ms2Slot);

        console2.log("");
        console2.log("=== MS2 ===");
        console2.log("  contract balance:", ms2Balance);
        console2.log("  custody owned:   ", uint256(ms2Owned));
        console2.log("  custody escrow:  ", uint256(ms2Escrow));

        uint256 ms2Accounted = uint256(ms2Owned) + uint256(ms2Escrow);
        if (ms2Balance > ms2Accounted) {
            console2.log("  UNACCOUNTED:     ", ms2Balance - ms2Accounted);
        }

        console2.log("");
        console2.log("=== Audit Complete ===");
    }

    function _split(bytes32 packed) internal pure returns (uint128 owned, uint128 escrow) {
        owned  = uint128(uint256(packed));
        escrow = uint128(uint256(packed) >> 128);
    }
}

/// @notice Drain all protocol-owned ETH and MS2 from the Foundation.
///         Requires the broadcaster to be the NFT owner.
contract DrainExecute is Script {
    address constant MS2 = 0x98Ed411B8cf8536657c660Db8aA55D9D4bAAf820;

    function run() external {
        address proxy = vm.envAddress("FOUNDATION_PROXY");
        IFoundation hub = IFoundation(proxy);

        console2.log("=== Foundation Drain ===");
        console2.log("Proxy:", proxy);
        console2.log("");

        // --- Pre-flight ---
        bytes32 ethKey = keccak256(abi.encodePacked(proxy, address(0)));
        (uint128 ethOwned, uint128 ethEscrow) = _split(hub.custody(ethKey));

        bytes32 ms2Key = keccak256(abi.encodePacked(proxy, MS2));
        (uint128 ms2Owned, uint128 ms2Escrow) = _split(hub.custody(ms2Key));

        uint256 ethBalance = proxy.balance;
        uint256 ms2Balance = IERC20(MS2).balanceOf(proxy);

        console2.log("ETH balance:", ethBalance);
        console2.log("ETH owned:  ", uint256(ethOwned));
        console2.log("MS2 balance:", ms2Balance);
        console2.log("MS2 owned:  ", uint256(ms2Owned));

        vm.startBroadcast();

        // 1. Withdraw protocol-owned ETH
        //    Owned (27.1e15) > balance (26.93e15) due to old accounting bugs.
        //    Withdraw only what's actually there to avoid revert.
        if (ethOwned > 0) {
            uint256 ethWithdraw = ethBalance < uint256(ethOwned) ? ethBalance : uint256(ethOwned);
            hub.withdrawProtocolOwned(address(0), ethWithdraw);
            console2.log("Withdrew ETH:", ethWithdraw);
        }

        // 2. Withdraw protocol-owned MS2
        if (ms2Owned > 0) {
            hub.withdrawProtocolOwned(MS2, uint256(ms2Owned));
            console2.log("Withdrew MS2 (owned):", uint256(ms2Owned));
        }

        // 3. Sweep unaccounted MS2 via performCalldata
        uint256 ms2Remaining = IERC20(MS2).balanceOf(proxy);
        if (ms2Remaining > 0) {
            hub.performCalldata(
                MS2,
                abi.encodeWithSelector(0xa9059cbb, msg.sender, ms2Remaining) // transfer(address,uint256)
            );
            console2.log("Swept unaccounted MS2:", ms2Remaining);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Drain Complete ===");
        console2.log("Remaining ETH:", proxy.balance);
        console2.log("Remaining MS2:", IERC20(MS2).balanceOf(proxy));
    }

    function _split(bytes32 packed) internal pure returns (uint128 owned, uint128 escrow) {
        owned  = uint128(uint256(packed));
        escrow = uint128(uint256(packed) >> 128);
    }
}
