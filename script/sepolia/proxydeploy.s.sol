// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {VaultRoot} from "src/VaultRoot.sol";

contract SepoliaDeploy is Script, CreateXScript {
    function setUp() public withCreateX {}

    function run() external {
        vm.startBroadcast();

        // 🧂 Magic Salt
        bytes32 salt = bytes32(abi.encodePacked(0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6, hex"00", bytes11(uint88(1708011))));
        address expectedAddr = computeCreate3Address(salt, 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6);

        address deployed = create3(salt, type(VaultRoot).creationCode);
        require(expectedAddr == deployed, "!!! Address mismatch");

        console2.log("OK! Deployed VaultAccount at:", deployed);

        vm.stopBroadcast();
    }
}
