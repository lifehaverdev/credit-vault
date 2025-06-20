// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultRoot} from "src/VaultRoot.sol";

contract MineVaultRootSalt is Script {

    address constant factory = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function run() external {
        vm.startBroadcast();
        address admin = msg.sender;
        console2.log("Mining for salt to be deployed by:", admin);
        
        uint256 start = vm.envOr("START", uint256(0));
        uint256 end = vm.envOr("END", uint256(1_000_000));

        bytes memory bytecode = type(VaultRoot).creationCode;
        bytes32 initCodeHash = keccak256(bytecode);
        console2.log("Mining initCodeHash:");
        console2.logBytes32(initCodeHash);

        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(uint256(i));
            bytes32 guardedSalt = keccak256(abi.encode(salt));

            address addr = address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xff), factory, guardedSalt, initCodeHash))
                    )
                )
            );

            if ((uint160(addr) >> 144) == 0x1152) {
                console2.log("!!OK!! Found matching salt:", i);
                console2.log("WOW! Computed address:", addr);
                console2.logBytes32(salt);
                console2.logBytes32(guardedSalt);
                break;
            }

            if (i % 1000 == 0) {
                console2.log("Checked:", i);
            }
        }

        vm.resumeGasMetering();
        vm.stopBroadcast();
    }
}
