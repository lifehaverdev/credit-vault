// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CREATEX_ADDRESS} from "lib/createx-forge/script/CreateX.d.sol";
import {ICreateX} from "lib/createx-forge/script/ICreateX.sol";

/// @title MineFoundationProxySalt
/// @notice Mines a vanity `PROXY_SALT` for deploying the Foundation hub proxy deterministically via
///         the ImmutableCreate2Factory.  The proxy address depends ONLY on `factory` + `salt`.
/// @dev This script is chain-agnostic – run it against any RPC.
///
/// Environment variables (all optional unless noted):
///   FACTORY        – ImmutableCreate2Factory address (default canonical)
///   TARGET_NIBBLE  – 12-bit prefix (upper nibble) to match in the resulting address (default: 0x115)
///   START          – first numeric salt to try (default 0)
///   END            – last numeric salt to try  (default 1_000_000)
///
/// Usage example:
///   forge script script/1-MineFoundationProxySalt.s.sol \
///     --fork-url $RPC_URL -vvvv
contract MineFoundationProxySalt is Script {
    // keccak256 hash of CreateX proxy child bytecode used in CREATE3 address derivation.
    bytes32 internal constant PROXY_CHILD_BYTECODE_HASH = 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    /// @dev Exact replica of CreateX.computeCreate3Address(salt, deployer)
    function _computeCreate3(bytes32 salt, address deployer) internal pure returns (address addr) {
        bytes32 computed;
        assembly {
            // Load free memory pointer so we can restore it later
            let ptr := mload(0x40)

            // ----------------------------------------------------------------
            // Build the 85-byte preimage in scratch space 0x00..0x60
            // ----------------------------------------------------------------
            mstore(0x00, deployer)                     // deployer (20 bytes)
            mstore8(0x0b, 0xff)                        // 0xff marker
            mstore(0x20, salt)                         // salt (32 bytes)
            mstore(0x40, PROXY_CHILD_BYTECODE_HASH)    // proxy child bytecode hash (32 bytes)

            // innerHash = keccak256(0xff ‖ salt ‖ hash) starting at 0x0b for 0x55 bytes
            mstore(0x14, keccak256(0x0b, 0x55))        // store at 0x14 to reuse buffer

            // Restore free memory pointer (gas-optimisation like in CreateX)
            mstore(0x40, ptr)

            // Write 0xd694 prefix and 0x01 suffix around innerHash → total slice len 0x17
            mstore(0x00, 0xd694)
            mstore8(0x34, 0x01)

            computed := keccak256(0x1e, 0x17)          // final hash
        }
        addr = address(uint160(uint256(computed)));
    }

    /// @notice Run the vanity-salt miner for CreateX / CREATE3.
    ///         The script searches for a raw salt (last 11 bytes vary) that – after
    ///         CreateX’s guarded-salt transformation – yields a proxy address with
    ///         the desired prefix.
    function run() external {
        console.log("CreateX factory:", CREATEX_ADDRESS);

        // ------------------------------------------------------------------
        // Target prefix inputs
        // ------------------------------------------------------------------

        // Attempt to fetch a hex string prefix from the environment.  Using `envString` reverts if the
        // variable is unset, so we wrap it in `try/catch` and fall back to an empty string when missing.
        string memory str;
        try vm.envString("TARGET_PREFIX_STR") returns (string memory fetched) {
            str = fetched;
        } catch {
            str = "0x01152"; // No string prefix supplied.
        }
        uint256 target;
        uint8 digits;

        if (bytes(str).length > 0) {
            // Strip optional 0x
            bytes memory bs = bytes(str);
            uint256 offset = (bs[0] == '0' && (bs.length > 1 && (bs[1] == 'x' || bs[1] == 'X'))) ? 2 : 0;
            digits = uint8(bs.length - offset);
            require(digits > 0 && digits <= 40, "bad str len");

            // Parse hex string to uint
            for (uint256 i = offset; i < bs.length; ++i) {
                uint8 c = uint8(bs[i]);
                uint8 val;
                if (c >= 0x30 && c <= 0x39) { // '0'..'9'
                    val = c - 0x30;
                } else if (c >= 0x61 && c <= 0x66) { // 'a'..'f'
                    val = 10 + (c - 0x61);
                } else if (c >= 0x41 && c <= 0x46) { // 'A'..'F'
                    val = 10 + (c - 0x41);
                } else {
                    revert("non-hex char");
                }
                target = (target << 4) | val;
            }
        } else {
            target = uint256(vm.envOr("TARGET_PREFIX", uint256(0)));
            uint8 autoDigits;
            uint256 tmp = target;
            while (tmp > 0) { autoDigits++; tmp >>= 4; }
            if (autoDigits == 0) autoDigits = 1;
            digits = uint8(vm.envOr("PREFIX_DIGITS", uint256(autoDigits)));
        }

        uint256 shift = 160 - 4 * digits;

        if (bytes(str).length > 0) {
            console.log("Target prefix (str):", str);
        }
        console.log("Target prefix (uint):", target);
        console.log("Digits to match:", digits);

        uint256 start = vm.envOr("START", uint256(628_000*3));
        uint256 end   = vm.envOr("END",   uint256(628_000*4));

        vm.startBroadcast();
        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            // Build the 32-byte raw salt where only the lower 88 bits vary.
            bytes32 rawSalt = bytes32(i);

            // Guard the salt – first 20 bytes = msg.sender, 21st byte = 0x00 (no cross-chain guard).
            bytes32 guardedSalt = keccak256(abi.encodePacked(uint256(uint160(msg.sender)), rawSalt));

            // Predict the proxy address that CreateX’s CREATE3 deploy will yield –
            // same formula the on-chain factory uses, but evaluated locally.
            address predicted = _computeCreate3(guardedSalt, CREATEX_ADDRESS);

            // One-off parity check against the factory’s own helper to catch any drift.
            if (i == start) {
                address remote = ICreateX(CREATEX_ADDRESS).computeCreate3Address(guardedSalt, CREATEX_ADDRESS);
                console.log("Remote predicted:", remote);
                if (remote != predicted) {
                    console.log("ERROR: local vs remote mismatch - aborting");
                    return;
                }
            }

            if ((uint160(predicted) >> shift) == target) {
                console.log("!!! Found vanity salt (raw/decimal):", i);
                console.log("rawSalt:");
                console.logBytes32(rawSalt);
                console.log("guardedSalt:");
                console.logBytes32(guardedSalt);
                console.log("Predicted proxy address:", predicted);
                break;
            }

            if (i % 1000 == 0) console.log("Checked:", i);
        }

        vm.resumeGasMetering();
        vm.stopBroadcast();
    }

    // No helper needed – prediction is delegated to the on-chain CreateX helper.
}
