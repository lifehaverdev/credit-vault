# Credit Vault Deployment Guide

This guide outlines how to deterministically deploy the VaultRoot implementation 
and ERC1967 proxy contracts with vanity addresses on Sepolia using Foundry.

## Prerequisites

- Foundry installed (https://book.getfoundry.sh/)
- Sepolia RPC fork available (via foundry.toml or CLI)
- ETH funded deployer address
- VaultRoot.sol compiled and available in src/

## Step 1: Mine a Vanity Salt for the Implementation

Uses the CreateX factory:
0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed

Script: scripts/MineVaultRootSalt.s.sol

Run:
  forge script scripts/MineVaultRootSalt.s.sol --fork-url $SEPOLIA_RPC --sender $YOUR_ADDRESS

Optional: Set START and END for the salt range:
  START=0 END=100000 forge script scripts/MineVaultRootSalt.s.sol --fork-url ...

Logs the salt and predicted address when found.

## Step 2: Deploy the Implementation

Script: scripts/DeployVaultRoot.s.sol

Update the salt in the script and deploy:
  forge script scripts/DeployVaultRoot.s.sol --fork-url $SEPOLIA_RPC --broadcast --sender $YOUR_ADDRESS

Success output:
  !WOW! Deployed VaultRoot to: 0x...

## Step 3: Mine a Vanity Salt for the Proxy

Uses the ERC1967 factory:
0x0000000000006396FF2a80c067f99B3d2Ab4Df24

Script: scripts/MineERC1967Salt.s.sol

Run:
  X=0 forge script scripts/MineERC1967Salt.s.sol --fork-url $SEPOLIA_RPC --sender $YOUR_ADDRESS

Logs a vanity match when found:
  !!WOW!! Found vanity address at salt: 318504

## Step 4: Deploy the Proxy and Initialize

Script: scripts/DeployProxy.s.sol

Update:
- IMPLEMENTATION = your deployed VaultRoot address
- salt = your mined vanity salt

Run:
  forge script scripts/DeployProxy.s.sol --fork-url $SEPOLIA_RPC --broadcast --sender $YOUR_ADDRESS

This uses `deployDeterministicAndCall()` to deploy and initialize in one step.

## Optional: Verify the Implementation Contract

You can verify the implementation on Etherscan using:

  forge verify-contract --chain-id 11155111 \
    0xYourImplementationAddress \
    src/VaultRoot.sol:VaultRoot \
    --etherscan-api-key $ETHERSCAN_KEY

Note: Etherscan may take time to detect the proxy contract correctly.

## Summary of Addresses

Component        | Address
-----------------|-----------------------------------------
Create2 Factory  | 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed
ERC1967 Factory  | 0x0000000000006396FF2a80c067f99B3d2Ab4Df24
VaultRoot Impl   | 0x115207b091Ea8ec2919C7F1368c6e1E5D1CC7207
Vanity Proxy     | 0x011528b1d5822B3269d919e38872cC33bdec6d17

## Local Testing

Run tests on Sepolia fork:

  forge test --fork-url $SEPOLIA_RPC

If you are simulating upgrades, use the deployed proxy address inside your tests.

