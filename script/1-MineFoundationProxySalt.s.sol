// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ERC1967Factory} from "lib/solady/src/utils/ERC1967Factory.sol";
import {ERC1967FactoryConstants} from "lib/solady/src/utils/ERC1967FactoryConstants.sol";

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
    address internal constant DEFAULT_FACTORY = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24;

    function run() external {
        address factory = DEFAULT_FACTORY;

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

        // Fetch the factory's deterministic init-code hash.  If the factory isn't
        // deployed on the current chain, fall back to the canonical constant.
        bytes32 initHash;
        if (factory.code.length == 0) {
            initHash = keccak256(ERC1967FactoryConstants.INITCODE);
            console.log("Factory not found on-chain; using canonical initHash");
        } else {
            initHash = ERC1967Factory(factory).initCodeHash();
        }
        console.log("Factory initCodeHash:");
        console.logBytes32(initHash);

        uint256 start = vm.envOr("START", uint256(1_319_000));
        uint256 end   = vm.envOr("END",   uint256(2_319_000));

        vm.startBroadcast();
        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(i);
            address predicted = _computeCreate2(factory, salt, initHash);
            if ((uint160(predicted) >> shift) == target) {
                console.log("!!! Found vanity salt:", i);
                console.log("Predicted proxy address:", predicted);
                console.logBytes32(salt);
                break;
            }
            if (i % 1000 == 0) console.log("Checked:", i);
        }

        vm.resumeGasMetering();
        vm.stopBroadcast();
    }

    function _computeCreate2(address deployer, bytes32 salt, bytes32 codeHash) internal pure returns (address addr) {
        addr = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, codeHash)))));
    }
}
