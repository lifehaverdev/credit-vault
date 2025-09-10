// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {Foundation} from "src/Foundation.sol";
import {CharteredFundImplementation} from "src/CharteredFundImplementation.sol";

/// @title DeployFoundationKeep
/// @notice Deploys the entire Charter infrastructure deterministically in **one transaction**.
///         Only the hub proxy's `PROXY_SALT` needs mining; other salts are fixed constants.
///
/// Environment variables (all required unless noted):
///   PROXY_SALT       – bytes32. Vanity-mined salt for the Foundation proxy.
///   OWNER_NFT        – address. NFT that controls protocol ownership.
///   OWNER_TOKEN_ID   – uint256. Token ID of the ownership NFT.
///
/// Optional env vars:
///   CHARTER_IMPL_SALT – bytes32 (default 0x01)
///   BEACON_SALT       – bytes32 (default 0x02)
///   IMPL_SALT         – bytes32 (default 0x03)  // Foundation implementation
///   FACTORY           – address of ImmutableCreate2Factory (default canonical)
///
/// Usage:
///   forge script script/2-DeployFoundationKeep.s.sol \
///     --fork-url $RPC_URL --broadcast --sender $DEPLOYER -vvvv
contract DeployFoundationKeep is Script {
    // Canonical ERC1967Factory address on most networks.
    address internal constant DEFAULT_FACTORY = 0x0000000000006396FF2a80c067f99B3d2Ab4Df24;

    struct DeployAddrs {
        address charterImpl;
        address charterBeacon;
        address foundationImpl;
        address proxy;
    }

    function run() external {
        // ---------------------------------------------------------------------
        // ENV
        // ---------------------------------------------------------------------
        bytes32 proxySalt      = vm.envBytes32("PROXY_SALT");
        console2.logBytes32(proxySalt);
        // ERC1967Factory address (optional override)
        address factoryAddr    = vm.envOr("FACTORY", DEFAULT_FACTORY);

        // ---------------------------------------------------------------------
        // Owner NFT settings (chain-aware defaults)
        // ---------------------------------------------------------------------

        (address defaultNft, uint256 defaultTokenId) = _defaultOwner();

        // If the env vars are missing, fall back to chain-specific defaults.
        address ownerNFT       = vm.envOr("OWNER_NFT", defaultNft);
        uint256 ownerTokenId   = vm.envOr("OWNER_TOKEN_ID", defaultTokenId);

        require(ownerNFT != address(0), "OWNER_NFT not set or unknown chain");

        console2.log("Owner NFT:", ownerNFT);
        console2.log("Owner tokenId:", ownerTokenId);

        ERC1967Factory factory = ERC1967Factory(factoryAddr);
        address predictedProxy = factory.predictDeterministicAddress(proxySalt);

        // Deploy contracts
        address charterImpl = address(new CharteredFundImplementation());
        address charterBeacon = address(new UpgradeableBeacon(msg.sender, charterImpl));
        address foundationImpl = address(new Foundation());

        console2.log("CharteredFundImplementation:", charterImpl);
        console2.log("UpgradeableBeacon:", charterBeacon);
        console2.log("Foundation implementation:", foundationImpl);
        console2.log("Foundation proxy:", predictedProxy);

        // Broadcast deployments
        vm.startBroadcast();

        // Deploy the proxy via factory, initializing it to point to the new beacon
        factory.deployDeterministicAndCall(
            foundationImpl,
            msg.sender,
            proxySalt,
            abi.encodeWithSelector(Foundation.initialize.selector, ownerNFT, ownerTokenId, charterBeacon)
        );

        vm.stopBroadcast();
    }

    /// @dev Provides per-chain defaults for the owner NFT & tokenId so the user
    ///      can skip setting them when deploying to common networks.
    function _defaultOwner() internal view returns (address nft, uint256 tokenId) {
        uint256 id = block.chainid;
        if (id == 1) {
            // Ethereum mainnet (example values – update to real ones)
            nft = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0; // Miladystation NFT
            tokenId = 114;
        } else if (id == 11155111) {
            // Sepolia testnet
            nft = 0x73eB323474B0597d3E20fBC4084D0E93f133a1ED; // MiladyCola Test Bottles
            tokenId = 46;
        } else if (id == 8453) {
            // Base mainnet
            nft = 0xa015F00D9782CEBb49E9a459b780adCD4E637b6E; // MCULT NFT
            tokenId = 35;
        } else {
            nft = address(0);
            tokenId = 0;
        }
    }

    // No helper needed anymore
}
