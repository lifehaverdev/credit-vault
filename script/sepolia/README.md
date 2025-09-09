# Credit Vault – Sepolia Deployment Guide (Deterministic & Cross-Chain)

This guide explains how to deterministically deploy the **Charter infrastructure** on any EVM chain.  The flow now uses a **beacon pattern** for all chartered funds and a **single Foundry script** (`DeployCharterInfra.s.sol`) that deploys every artefact in one transaction.

---

## Prerequisites

• Foundry installed – <https://book.getfoundry.sh/>  
• A Sepolia RPC endpoint (`$SEPOLIA_RPC`)  
• ETH-funded wallets:  
  - **IMPL_DEPLOYER** – *virgin* wallet (nonce-0). Its address is baked into the CREATE3 formula, so it **must be identical across chains**.  
  - **PROXY_ADMIN** – wallet that will own the hub proxy. (Hard-coded in the proxy constructor.)  
  - **CALLER_WALLET** – wallet that broadcasts the transaction (often the same as `PROXY_ADMIN`).
• Contracts compiled (`forge build`).

---

## Deterministic Inputs

| Purpose | Value | Notes |
|---------|-------|-------|
| CREATE3 Deployer | keyless CREATE3 contract (canonical, same on every chain) | Used by `CREATE3.deployDeterministic()` |
| `IMPL_SALT` | vanity/fixed bytes32 | **Foundation** implementation |
| `CHARTER_IMPL_SALT` | vanity/fixed bytes32 | **CharteredFund** implementation |
| `BEACON_SALT` | vanity/fixed bytes32 | **UpgradeableBeacon** for funds |
| ImmutableCreate2Factory | `0x0000000000FFe8B47B3e2130213B802212439497` | 0age’s factory – exists on many chains |
| `PROXY_SALT` | vanity/fixed bytes32 | Determines the hub proxy’s vanity prefix |
| Proxy admin | **PROXY_ADMIN** address | Hard-coded into the proxy constructor |

Lock those inputs and you will obtain the *same addresses on every chain*.

---

## Step 1 – Mine a Vanity Salt for the Foundation Implementation

```bash
forge script script/sepolia/MineFoundationImplSalt.s.sol \
  --fork-url $SEPOLIA_RPC \
  --sender $IMPL_DEPLOYER
```

Save the winning `IMPL_SALT` to your `.env`.

---

## Step 2 – Deploy the Foundation Implementation (CREATE3)

```bash
IMPL_SALT=<your-salt> \
forge script script/sepolia/DeployFoundationImplementation.s.sol \
  --fork-url $SEPOLIA_RPC \
  --broadcast \
  --sender $IMPL_DEPLOYER
```

Commit the emitted address to the table above.

---

## Step 2.1 – Deploy the CharteredFund Implementation (CREATE3)

```bash
CHARTER_IMPL_SALT=<your-salt> \
forge script script/sepolia/DeployCharterInfra.s.sol --sig "addresses()" | grep CharteredFundImplementation
```

> The unified script `DeployCharterInfra` already contains the logic to deploy this contract; you only need to supply the salt.  This step is shown for completeness when you wish to broadcast individual components.

---

## Step 2.2 – Deploy the UpgradeableBeacon (CREATE3)

```bash
BEACON_SALT=<your-salt>
# Beacon constructor args are (owner, implementation)
# The unified script will handle that automatically.
```

Again, `DeployCharterInfra` will perform this deployment automatically.  Run the separate step only if you prefer a manual flow.

---

## Step 3 – Mine a Vanity Salt for the Proxy (optional)

```bash
forge script script/sepolia/MineERC1967Salt.s.sol \
  --fork-url $SEPOLIA_RPC \
  --sender $YOUR_ADDRESS \
  -vvvv
```

Save the `PROXY_SALT` you like.

---

## Step 4 – Run the Unified Deployment Script

```bash
CHARTER_IMPL_SALT=<salt> \
BEACON_SALT=<salt> \
IMPL_SALT=<salt> \
PROXY_SALT=<salt> \
OWNER_NFT=<erc721-address> \
OWNER_TOKEN_ID=<tokenId> \
forge script script/sepolia/DeployCharterInfra.s.sol \
  --fork-url $SEPOLIA_RPC \
  --broadcast \
  --sender $CALLER_WALLET \
  -vvvv
```

Expected console output (dry-run):

```
Predicted CharteredFundImplementation: 0x11AB…
Predicted UpgradeableBeacon:         0xBEEF…
Predicted Foundation implementation: 0x1152…
Predicted Foundation proxy:          0x01152…
```

Running with `--broadcast` deploys **all four artefacts in one transaction** and calls `initialize(ownerNFT, ownerTokenId, beacon)` on the hub proxy.

Repeat this step on any chain with the same salts & wallets and you will reproduce the exact same addresses.

---

## Upgrading Hub + All Funds (single transaction)

Because every chartered fund is a **Beacon proxy**, upgrading the beacon automatically upgrades *all* funds atomically.  From the hub you can upgrade in one call:

```solidity
// Called via the hub proxy
Foundation.upgradeCharterImplementation(newImplementation);
```

The hub forwards the call to `UpgradeableBeacon.upgradeTo(newImplementation)`, updating the implementation for every existing and future fund.

---

## Optional – Verify Implementation on Etherscan

```bash
forge verify-contract \
  --chain-id 11155111 \
  0xYourImplementationAddress \
  src/Foundation.sol:Foundation \
  --etherscan-api-key $ETHERSCAN_KEY
```

---

## Summary of Deterministic Addresses (Sepolia example)

| Component | Address |
|-----------|---------|
| CREATE3 Deployer | *canonical* |
| CharteredFund implementation | `0x11AB…` |
| Foundation implementation | `0x1152…` |
| UpgradeableBeacon | `0xBEEF…` |
| ImmutableCreate2Factory | `0x0000000000FFe8B47B3e2130213B802212439497` |
| Hub Proxy (ERC1967) | `0x01152…` |

---

## Local Testing

```bash
forge test --fork-url $SEPOLIA_RPC
```

Use the deterministic addresses inside your tests when needed.

