// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";

contract SepoliaMineSalt is Script, CreateXScript {
    function run() external {
        address deployer = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;

        // Allow range override via environment
        uint256 start = vm.envOr("START", uint256(0));
        uint256 end = vm.envOr("END", uint256(1_000_000));

        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(abi.encodePacked(deployer, hex"00", bytes11(uint88(i))));
            address computed = computeCreate3Address(salt, deployer);

            // Match against vanity prefix (first 20 bits == 0x01152)
            if ((uint160(computed) >> (160 - 20)) == 0x01152) {
                console2.log("!!!! Found Salt:", uint88(i));
                console2.log("Computed Address:", computed);
                break;
            }

            if (i < 10) {
                console2.log("i:", i);
                console2.log("computed:", computed);
            }

            if (i % 1000 == 0) {
                console2.log("Checked up to:", i);
            }
        }

        vm.resumeGasMetering();
    }
}
