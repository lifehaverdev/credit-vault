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
        address charterImpl   = vm.envOr("CHARTER_IMPL", address(0));
        address charterBeacon = vm.envOr("CHARTER_BEACON", address(0));
        address foundationImpl = vm.envOr("FOUNDATION_IMPL", address(0));
        address foundationProxy = vm.envOr("FOUNDATION_PROXY", address(0));
        address deployer = vm.envOr("DEPLOYER", address(0));

        uint256 chainId = vm.envOr("CHAIN_ID", block.chainid);

        console2.log("\n================== Verification Commands ==================");

        // CharteredFundImplementation ----------------------------------------------------
        if (charterImpl != address(0)) {
            console2.log("1) CharteredFundImplementation:\n");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(charterImpl),
                    " src/CharteredFundImplementation.sol:CharteredFundImplementation",
                    " --chain-id ", vm.toString(chainId),
                    ""
                )
            );
        }

        // UpgradeableBeacon ----------------------------------------------------------------
        if (charterBeacon != address(0) && charterImpl != address(0) && deployer != address(0)) {
            console2.log("\n2) UpgradeableBeacon (constructor args auto-encoded):\n");
            bytes memory ctorArgs = abi.encode(deployer, charterImpl);
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(charterBeacon),
                    " lib/solady/src/utils/UpgradeableBeacon.sol:UpgradeableBeacon",
                    " --constructor-args ", vm.toString(ctorArgs),
                    " --chain-id ", vm.toString(chainId),
                    ""
                )
            );
        }

        // Foundation implementation --------------------------------------------------------
        if (foundationImpl != address(0)) {
            console2.log("\n3) Foundation implementation:\n");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(foundationImpl),
                    " src/Foundation.sol:Foundation",
                    " --chain-id ", vm.toString(chainId),
                    ""
                )
            );
        }

        // Foundation proxy -----------------------------------------------------------------
        if (foundationProxy != address(0)) {
            console2.log("\n4) Foundation proxy (verify as implementation):\n");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(foundationProxy),
                    " src/Foundation.sol:Foundation",
                    " --chain-id ", vm.toString(chainId),
                    ""
                )
            );
        }

        console2.log("\n===========================================================\n");
    }
}
