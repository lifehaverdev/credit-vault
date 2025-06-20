// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultRoot} from "src/VaultRoot.sol";

// Use the existing implementation contract
address payable constant IMPLEMENTATION = payable(0x115207b091Ea8ec2919C7F1368c6e1E5D1CC7207);
address constant FACTORY = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24;

interface IERC1967Factory {
    function deployDeterministicAndCall(
        address implementation,
        address admin,
        bytes32 salt,
        bytes calldata data
    ) external payable returns (address proxy);
}

contract DeployProxy is Script {
    function run() external {
        vm.startBroadcast();

        address admin = msg.sender;
        bytes32 salt = bytes32(uint256(318504)); // your vanity salt
        VaultRoot impl = VaultRoot(IMPLEMENTATION);
        // Use empty initializer
        bytes memory initCalldata = abi.encodeCall(impl.initialize, ());

        address proxy = IERC1967Factory(FACTORY).deployDeterministicAndCall(
            IMPLEMENTATION,
            admin,
            salt,
            initCalldata
        );

        console.log("!!WOW!! Proxy deployed and initialized at:", proxy);
        vm.stopBroadcast();
    }
}
