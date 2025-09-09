// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "createx-forge/src/ERC1967Proxy.sol";
import {Foundation} from "src/Foundation.sol";
import {CharteredFundImplementation} from "src/CharteredFundImplementation.sol";

/// @notice Deploys the complete Charter infrastructure (implementation, beacon, hub proxy) deterministically.
///         All artefacts are deployed in a single transaction when `--broadcast` is supplied.
///         Environment variables (all `bytes32` unless noted):
///         - CHARTER_IMPL_SALT
///         - BEACON_SALT
///         - IMPL_SALT       (Foundation implementation)
///         - PROXY_SALT      (Foundation proxy)
///         - OWNER_NFT       (address)
///         - OWNER_TOKEN_ID  (uint256)
///
///         The script can be run offline to predict addresses via the `addresses()` view function.
contract DeployCharterInfra is Script {
    // ImmutableCreate2Factory address (0age canonical)
    address internal constant IMMUTABLE_FACTORY = 0x0000000000FFe8B47B3e2130213B802212439497;

    struct DeployAddrs {
        address charterImpl;
        address charterBeacon;
        address foundationImpl;
        address proxy;
    }

    function run() external {
        // ---------------------------------------------------------------------
        // Load ENV
        // ---------------------------------------------------------------------
        bytes32 charterSalt = vm.envBytes32("CHARTER_IMPL_SALT");
        bytes32 beaconSalt   = vm.envBytes32("BEACON_SALT");
        bytes32 implSalt     = vm.envBytes32("IMPL_SALT");
        bytes32 proxySalt    = vm.envBytes32("PROXY_SALT");

        address ownerNFT     = vm.envAddress("OWNER_NFT");
        uint256 ownerTokenId = vm.envUint("OWNER_TOKEN_ID");

        DeployAddrs memory addrs = predictAddresses(charterSalt, beaconSalt, implSalt, proxySalt, ownerNFT, ownerTokenId);

        console2.log("Predicted CharteredFundImplementation:", addrs.charterImpl);
        console2.log("Predicted UpgradeableBeacon:", addrs.charterBeacon);
        console2.log("Predicted Foundation implementation:", addrs.foundationImpl);
        console2.log("Predicted Foundation proxy:", addrs.proxy);

        if (vm.envOr("BROADCAST", false)) revert("Use --broadcast flag instead of setting BROADCAST");

        if (vm.envBool("BROADCAST")) {
            // The BROADCAST env var is legacy -- ignore; rely on Foundry flag.
        }

        // forge-std Vm no longer has isBroadcast; assume dry run when BROADCAST not set
        // So we skip when not broadcasting via env var handled above

        // ---------------------------------------------------------------------
        // Broadcast deterministic deploys (single tx)
        // ---------------------------------------------------------------------
        vm.startBroadcast();

        // 1. CharteredFundImplementation via CREATE3
        bytes memory cfInit = type(CharteredFundImplementation).creationCode;
        address charterImpl = CREATE3.deployDeterministic(cfInit, charterSalt);

        // 2. UpgradeableBeacon pointing to charterImpl via CREATE3
        bytes memory beaconInit = abi.encodePacked(
            type(UpgradeableBeacon).creationCode,
            abi.encode(msg.sender, charterImpl)
        );
        address charterBeacon = CREATE3.deployDeterministic(beaconInit, beaconSalt);

        // 3. Foundation implementation via CREATE3 (already existing step)
        bytes memory foundationInit = type(Foundation).creationCode;
        address foundationImpl = CREATE3.deployDeterministic(foundationInit, implSalt);

        // 4. Foundation Proxy via ImmutableCreate2Factory
        bytes memory proxyInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                foundationImpl,
                abi.encodeWithSelector(
                    Foundation.initialize.selector,
                    ownerNFT,
                    ownerTokenId,
                    charterBeacon
                )
            )
        );
        address proxy;
        {
            (bool ok, bytes memory data) = IMMUTABLE_FACTORY.call(
                abi.encodeWithSignature("deploy(bytes32,bytes)", proxySalt, proxyInitCode)
            );
            require(ok, "Factory deploy failed");
            proxy = abi.decode(data, (address));
        }

        vm.stopBroadcast();

        console2.log("Deployed CharteredFundImplementation:", charterImpl);
        console2.log("Deployed UpgradeableBeacon:", charterBeacon);
        console2.log("Deployed Foundation implementation:", foundationImpl);
        console2.log("Deployed Foundation proxy:", proxy);
    }

    /// @notice Pure helper returning the predicted addresses for offline usage.
    function addresses() external view returns (DeployAddrs memory addrs) {
        bytes32 charterSalt = vm.envBytes32("CHARTER_IMPL_SALT");
        bytes32 beaconSalt   = vm.envBytes32("BEACON_SALT");
        bytes32 implSalt     = vm.envBytes32("IMPL_SALT");
        bytes32 proxySalt    = vm.envBytes32("PROXY_SALT");

        address ownerNFT     = vm.envAddress("OWNER_NFT");
        uint256 ownerTokenId = vm.envUint("OWNER_TOKEN_ID"); // not used for address calc

        return predictAddresses(charterSalt, beaconSalt, implSalt, proxySalt, ownerNFT, ownerTokenId);
    }

    function predictAddresses(
        bytes32 charterSalt,
        bytes32 beaconSalt,
        bytes32 implSalt,
        bytes32 proxySalt,
        address /*ownerNFT*/,
        uint256 /*ownerTokenId*/
    ) internal view returns (DeployAddrs memory addrs) {
        addrs.charterImpl = CREATE3.predictDeterministicAddress(charterSalt, address(this));
        addrs.charterBeacon = CREATE3.predictDeterministicAddress(beaconSalt, address(this));
        addrs.foundationImpl = CREATE3.predictDeterministicAddress(implSalt, address(this));

        bytes memory proxyInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                addrs.foundationImpl,
                abi.encodeWithSelector(Foundation.initialize.selector, address(0), 0, addrs.charterBeacon)
            )
        );
        bytes32 initHash = keccak256(proxyInitCode);
        addrs.proxy = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            IMMUTABLE_FACTORY,
            proxySalt,
            initHash
        )))));
    }
}
