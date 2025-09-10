// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

/// @title VerifyFoundationKeep
/// @notice Utility script that prints ready-to-run `forge verify-contract` commands for
///         the contracts deployed by `2-DeployFoundationKeep.s.sol`.
///
/// Environment variables (all required):
///   CHARTER_IMPL      – address of the deployed `CharteredFundImplementation`.
///   CHARTER_BEACON    – address of the deployed `UpgradeableBeacon`.
///   FOUNDATION_IMPL   – address of the deployed `Foundation` implementation.
///   FOUNDATION_PROXY  – address of the ERC1967 proxy (deployed via CreateX / CREATE3).
///   DEPLOYER          – address that performed the deployment (initial owner of the beacon).
///
/// Optional env vars:
///   CHAIN_ID          – chainId override (defaults to `block.chainid`).
///
/// Usage:
///   forge script script/utils/verify.s.sol -vvvv
///
/// Copy-paste the printed commands or `eval` them in your shell.  Each command already includes
/// `--watch` so it will poll until the verification is processed.
contract VerifyFoundationKeep is Script {
    function run() external view {
        // ---------------------------------------------------------------------
        // Read env vars
        // ---------------------------------------------------------------------
        address charterImpl      = vm.envAddress("CHARTER_IMPL");
        address charterBeacon    = vm.envAddress("CHARTER_BEACON");
        address foundationImpl   = vm.envAddress("FOUNDATION_IMPL");
        address foundationProxy  = vm.envAddress("FOUNDATION_PROXY");
        address deployer         = vm.envAddress("DEPLOYER");

        uint256 chainId = vm.envOr("CHAIN_ID", block.chainid);

        console2.log("\n================== Verification Commands ==================");

        // CharteredFundImplementation ----------------------------------------------------
        console2.log("1) CharteredFundImplementation:\n");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(charterImpl),
                " src/CharteredFundImplementation.sol:CharteredFundImplementation",
                " --chain-id ", vm.toString(chainId),
                " --watch"
            )
        );

        // UpgradeableBeacon ----------------------------------------------------------------
        console2.log("\n2) UpgradeableBeacon (constructor args: <deployer> <impl>):\n");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(charterBeacon),
                " solady/utils/UpgradeableBeacon.sol:UpgradeableBeacon ",
                vm.toString(deployer), " ", vm.toString(charterImpl),
                " --chain-id ", vm.toString(chainId),
                " --watch"
            )
        );

        // Foundation implementation --------------------------------------------------------
        console2.log("\n3) Foundation implementation:\n");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(foundationImpl),
                " src/Foundation.sol:Foundation",
                " --chain-id ", vm.toString(chainId),
                " --watch"
            )
        );

        // Foundation proxy -----------------------------------------------------------------
        console2.log("\n4) Foundation proxy (verify as implementation):\n");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(foundationProxy),
                " src/Foundation.sol:Foundation",
                " --chain-id ", vm.toString(chainId),
                " --watch"
            )
        );

        console2.log("\n===========================================================\n");
    }
}
