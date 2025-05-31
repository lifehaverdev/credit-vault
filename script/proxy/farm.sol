// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {AiCreditVault} from "../../src/implementation/CreditVault.sol";

contract FarmVanitySalt is Script {
    bytes2 constant TARGET_PREFIX = 0x1152;

    function run(address implementation) external view {
        address factory = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24; // Replace with actual factory
        address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6; // The owner/admin of the deployed proxy

        // Init calldata: encode initialize(tokens[], backend)
        address[] memory tokens = new address[](1);
        tokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Example: USDC
        address backend = implementation;

        bytes memory initData = abi.encodeWithSelector(
            AiCreditVault.initialize.selector,
            tokens,
            backend
        );

        // Get the init code hash from the factory
        ERC1967Factory f = ERC1967Factory(factory);
        bytes32 initCodeHash = f.initCodeHash();

        console.log("Init code hash:", toHex(initCodeHash));
        console.log("Searching for salt...");

        for (uint256 i = 0; i < 1_000_000; i++) {
            // Salt format: pack admin into upper 160 bits
            bytes32 salt = bytes32(bytes.concat(bytes20(admin), bytes12(uint96(i))));

            address predicted = computeCreate2(factory, salt, initCodeHash);

            if (uint16(uint160(predicted)) == uint16(TARGET_PREFIX)) {
                console.log("Found salt!");
                console.log("Salt:", toHex(salt));
                console.log("Address:", predicted);
                break;
            }
        }
    }

    function computeCreate2(address factory, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            factory,
            salt,
            initCodeHash
        )))));
    }

    function toHex(bytes32 data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; ++i) {
            str[i * 2] = hexChars[uint8(data[i] >> 4)];
            str[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
