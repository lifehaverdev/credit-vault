# Credit Vault – Sepolia Deployment Guide (Deterministic & Cross-Chain)

This guide walks through deploying the **Foundation** implementation deterministically with CREATE3 and then deploying an **ERC1967 proxy** at a vanity address via the ImmutableCreate2Factory.  Following these steps on any EVM chain will reproduce the *exact* same proxy address.

---

## Prerequisites

• Foundry installed – <https://book.getfoundry.sh/>  
• A Sepolia RPC endpoint (`$SEPOLIA_RPC`)  
• ETH-funded wallets:  
  - **IMPL_DEPLOYER** – *virgin* wallet (nonce-0). Its address is baked into the CREATE3 formula, so it **must be the same on every chain**. After deployment you may reuse it, but keep its nonce identical across chains if you redeploy.  
  - **PROXY_ADMIN** – any wallet whose address will become the proxy admin. It does **not** influence the CREATE2 address, but keep it constant for consistency.  
  - **CALLER_WALLET** – the wallet that actually broadcasts the proxy deployment tx (often the same as `PROXY_ADMIN`).
• Contracts compiled (`forge build`).

---

## Deterministic Inputs

| Purpose | Value | Notes |
|---------|-------|-------|
| CREATE3 Deployer | keyless CREATE3 contract (canonical, same on every chain) | Used by `CREATE3.deployDeterministic()` |
| `IMPL_SALT` | vanity-mined bytes32 | Produces a pretty implementation address |
| ImmutableCreate2Factory | `0x0000000000FFe8B47B3e2130213B802212439497` | 0age’s factory – exists on many chains |
| `PROXY_SALT` | vanity-mined bytes32 | Determines the proxy’s vanity prefix |
| Proxy admin | **PROXY_ADMIN** address | Hard-coded into the proxy constructor |

Lock those five inputs and you get the same proxy address on every chain.

---

## Step 1 – Mine a Vanity Salt for the Implementation

```
forge script script/sepolia/MineFoundationImplSalt.s.sol \
  --fork-url $SEPOLIA_RPC \
  --sender $IMPL_DEPLOYER
```

The script sweeps a salt range until it finds an implementation address you like. Save the winning `IMPL_SALT` to your `.env`.

---

## Step 2 – Deploy the Foundation Implementation (CREATE3)

```
IMPL_SALT=<your-salt> \
forge script script/sepolia/DeployFoundationImplementation.s.sol \
  --fork-url $SEPOLIA_RPC \
  --broadcast \
  --sender $IMPL_DEPLOYER
```

Successful output:
```
Foundation implementation deployed at: 0x1152…
```
The address should match what you computed during mining. Commit it to the address table below.

---

## Step 3 – Mine a Vanity Salt for the Proxy (optional)

```
forge script script/sepolia/MineERC1967Salt.s.sol \
  --fork-url $SEPOLIA_RPC \
  --sender $YOUR_ADDRESS \
  -vvvv
```

The script searches for a salt where the predicted proxy address starts with `0x01152…`. Save the `PROXY_SALT`.

---

## Step 4 – Deploy the Proxy & Initialize

```
IMPL_ADDRESS=<implementation-addr> \
OWNER_NFT=<erc721-address> \
OWNER_TOKEN_ID=<tokenId> \
PROXY_SALT=<your-salt> \
forge script script/sepolia/DeployFoundationProxy.s.sol \
  --fork-url $SEPOLIA_RPC \
  --broadcast \
  --sender $CALLER_WALLET
```

• The script can be sent from any wallet (`CALLER_WALLET`).  
• The proxy admin address is set to `PROXY_ADMIN` in the constructor.  
• The script deploys the proxy via the factory, then calls `initialize(ownerNFT, ownerTokenId)` in the same tx.

Expected console output:
```
Proxy deployed to: 0x01152…
Proxy initialised.
```

Repeat Steps 2-4 on any other chain with the same salts and wallets and you will receive the exact same proxy address.

---

## Optional – Verify Implementation on Etherscan

```
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
| Implementation (Foundation) | `0x1152…` |
| ImmutableCreate2Factory | `0x0000000000FFe8B47B3e2130213B802212439497` |
| Proxy (ERC1967) | `0x01152…` |

---

## Local Testing

```
forge test --fork-url $SEPOLIA_RPC
```

Use the deterministic proxy address inside your tests when needed.

