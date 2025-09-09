// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "createx-forge/src/ERC1967Proxy.sol";

/// @notice Mines a vanity `PROXY_SALT` such that the hub proxy deployed via
///         the ImmutableCreate2Factory shares the same upper-nibble vanity
///         prefix as the already-mined `Foundation` implementation.
///
/// Environment variables (all optional unless noted):
///   IMPL_ADDRESS   – required. Deployed / predicted Foundation implementation.
///   PROXY_ADMIN    – required. Admin address embedded in constructor.
///   OWNER_NFT      – ERC-721 contract whose NFToken identifies the protocol owner.
///   OWNER_TOKEN_ID – tokenId of the ownership NFT.
///   BEACON_ADDR    – predicted UpgradeableBeacon address.
///   FACTORY        – ImmutableCreate2Factory address (default canonical).
///   TARGET_NIBBLE  – uint256 upper-12-bit nibble to match (default impl >> 140).
///   START          – first numeric salt to try (default 0)
///   END            – last numeric salt to try  (default 1_000_000)
///
/// Usage (example):
///   PROXY_ADMIN=0x1152… \
///   IMPL_ADDRESS=0x011523… \
///   forge script script/sepolia/MineProxySalt.s.sol:MineProxySalt -vvvv
contract MineProxySalt is Script {
    address internal constant DEFAULT_FACTORY = 0x0000000000FFe8B47B3e2130213B802212439497;

    function run() external {
        address factory = vm.envOr("FACTORY", DEFAULT_FACTORY);
        address implementation = 0x0115230479772738DD3C8Dd80965690F7f95De7c;//gotten from 1-MineFoundationImplSalt.s.sol//vm.envAddress("IMPL_ADDRESS");
        address proxyAdmin = vm.envAddress("ADMIN");

        // Optional args for initialise selector – if omitted we still brute-force
        // the salt, because the encoded calldata affects the initCodeHash.
        address ownerNFT      = vm.envOr("OWNER_NFT", address(0));
        uint256 ownerTokenId  = vm.envOr("OWNER_TOKEN_ID", uint256(0));
        address beacon        = vm.envOr("BEACON_ADDR", address(0));

        // Pre-encode the proxy init code ______________________________________
        bytes memory initCalldata = abi.encodeWithSelector(
            bytes4(0x8129fc1c), // Foundation.initialize.selector hard-coded to avoid importing.
            ownerNFT,
            ownerTokenId,
            beacon
        );
        bytes memory proxyInit = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, proxyAdmin, initCalldata)
        );
        bytes32 initHash = keccak256(proxyInit);

        // Vanity target nibble (upper 12 bits)
        uint256 targetNibble = vm.envOr("TARGET_NIBBLE", uint256(uint160(implementation) >> 140));
        console2.log("Target nibble:", targetNibble);
        console2.log("Init code hash:");
        console2.logBytes32(initHash);

        uint256 start = vm.envOr("START", uint256(0));
        uint256 end   = vm.envOr("END",   uint256(1_000_000));

        vm.startBroadcast();
        vm.pauseGasMetering();

        for (uint256 i = start; i < end; ++i) {
            bytes32 salt = bytes32(i);
            address predicted = computeCreate2(factory, salt, initHash);
            if ((uint160(predicted) >> 140) == targetNibble) {
                console2.log("!! WOW !! Found matching proxy salt:", i);
                console2.log("Predicted proxy address:", predicted);
                console2.logBytes32(salt);
                break;
            }
            if (i % 1000 == 0) {
                console2.log("Checked:", i);
            }
        }

        vm.resumeGasMetering();
        vm.stopBroadcast();
    }

    function computeCreate2(address deployer, bytes32 salt, bytes32 codeHash) internal pure returns (address addr) {
        addr = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), deployer, salt, codeHash
        )))));
    }
} 