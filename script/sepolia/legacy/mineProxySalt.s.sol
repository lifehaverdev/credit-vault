// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract MineERC1967Salt is Script {
    address constant factory = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24;
    bytes32 constant initCodeHash = 0x4435a5963c29bc1c221d8cfc9c546a167425b5e1f4b5017cc0a0dd4ccaac27d1;

    function run() external {
        vm.startBroadcast();

        uint256 x = vm.envOr("X", uint256(0));
        uint256 lim = 54000;
        uint256 start = vm.envOr("START", uint256(lim * x));
        uint256 end = vm.envOr("END", uint256(lim * (x + 1)));

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(i);
            address predicted = computeCreate2(factory, salt, initCodeHash);

            if ((uint160(predicted) >> 140) == 0x01152) {
                console2.log("!!WOW!! Found vanity address at salt:", i);
                console2.log("Address:", predicted);
                console2.logBytes32(salt);
                break;
            }

            if (i % 1000 == 0) {
                console2.log("Checked:", i);
            }
        }

        vm.stopBroadcast();
    }

    function computeCreate2(address deployer, bytes32 salt, bytes32 codeHash) internal pure returns (address addr) {
        addr = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            codeHash
        )))));
    }
}
