// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {ICreateX} from "lib/createx-forge/script/ICreateX.sol";
import {CREATEX_ADDRESS} from "lib/createx-forge/script/CreateX.d.sol";
import {CreditVault} from "src/CreditVault.sol";

ICreateX constant CreateX = ICreateX(CREATEX_ADDRESS);

/// @notice Deploys CreditVault as a UUPS proxy with a deterministic address via CreateX CREATE3.
///
/// Environment variables:
///   PROXY_SALT  – bytes32. Salt for the proxy (mine with script 1 if vanity desired).
///   OWNER       – address. Initial owner of the vault.
///
/// Deploys to the same address on any EVM chain using the same salt.
///
/// Usage (mainnet):
///   forge script script/DeployCreditVault.s.sol \
///     --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
///
/// Usage (Base):
///   forge script script/DeployCreditVault.s.sol \
///     --fork-url $BASE_RPC_URL --broadcast --account <keystore-name> -vvvv
contract DeployCreditVault is Script {
    function run() external {
        bytes32 proxySalt = vm.envBytes32("PROXY_SALT");
        address vaultOwner = vm.envOr("OWNER", msg.sender);

        vm.startBroadcast();

        address impl = address(new CreditVault());
        console2.log("CreditVault implementation:", impl);

        bytes memory initCode = LibClone.initCodeERC1967(impl);
        address proxy = CreateX.deployCreate3AndInit(
            proxySalt,
            initCode,
            abi.encodeCall(CreditVault.initialize, (vaultOwner)),
            ICreateX.Values(0, 0)
        );

        console2.log("CreditVault proxy:", proxy);
        console2.log("Owner:", vaultOwner);
        console2.log("Chain:", block.chainid);

        vm.stopBroadcast();
    }
}
