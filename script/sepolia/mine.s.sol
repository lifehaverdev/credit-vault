// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {VaultRoot} from "src/VaultRoot.sol";

contract MineVaultRootSalt is Script {
    function setUp() public {}

    function run() external {
        address deployer = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;

        uint256 start = vm.envOr("START", uint256(0));
        uint256 end = vm.envOr("END", uint256(1_000_000));

        bytes memory bytecode = type(VaultRoot).creationCode;
        bytes32 initCodeHash = keccak256(bytecode);

        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(uint256(i));

            address addr = vm.computeCreate2Address(salt, initCodeHash, deployer);

            if ((uint160(addr) >> 144) == 0x1152){
                console2.log("!!OK!! Found matching salt:", i);
                console2.log("WOW! Computed address:", addr);
                console2.logBytes32(salt);
                break;
            }

            if (i % 1000 == 0) {
                console2.log("Checked:", i);
            }
        }

        vm.resumeGasMetering();
    }
}
