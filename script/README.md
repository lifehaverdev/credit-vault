# Credit Vault – Sepolia Deterministic Deployment Guide

This guide documents the **simplified, fully deterministic** deployment flow for the
Charter infrastructure on **any EVM chain**.

All four on-chain artefacts are deployed in one transaction via Foundry scripts
and their addresses depend **only on the salts you choose** – never on wallet
nonces or constructor arguments.

---

## Prerequisites

• Foundry installed – <https://book.getfoundry.sh/>  
• A Sepolia RPC endpoint (`$SEPOLIA_RPC`)  
• Any ETH-funded wallet capable of signing & broadcasting transactions
  (`$BROADCASTER`).  
• Contracts compiled (`forge build`).

---

## Deterministic Inputs

| Key | Purpose | Notes |
|-----|---------|-------|
| `IMPL_SALT` | Foundation implementation (CREATE3) | vanity/fixed `bytes32` |
| `CHARTER_IMPL_SALT` | CharteredFund implementation (CREATE3) | vanity/fixed `bytes32` |
| `BEACON_SALT` | UpgradeableBeacon (CREATE3) | vanity/fixed `bytes32` |
| `PROXY_SALT` | Foundation hub proxy (ERC-1967) | only input that affects any address |
| ERC1967Factory | `0x0000000000006396FF2a80c067f99B3d2Ab4Df24` | canonical factory |

Locking these inputs guarantees the **same addresses on every chain**.

> **Call-out:** the hub proxy’s address depends *solely* on `PROXY_SALT`.
> Implementation bytecode, admin address, calldata, and broadcasting wallet do
> **not** influence the derived address.

---

## 1. Mine Salts

### 1.1 Foundation implementation

```bash
forge script script/sepolia/1-MineFoundationImplSalt.s.sol \
  --fork-url $SEPOLIA_RPC
```

### 1.2 Hub proxy

```bash
forge script script/1-MineFoundationProxySalt.s.sol \
  --fork-url $SEPOLIA_RPC
```

The script searches numeric salts until it finds a proxy address with your preferred prefix.  Export the printed value as `PROXY_SALT`.

---

## 2. One-Shot Deployment

```bash
IMPL_SALT=<hex32> \
CHARTER_IMPL_SALT=<hex32> \
BEACON_SALT=<hex32> \
PROXY_SALT=<hex32> \
OWNER_NFT=<address> \
OWNER_TOKEN_ID=<uint256> \
forge script script/2-DeployFoundationKeep.s.sol \
  --fork-url $SEPOLIA_RPC \
  --broadcast \
  --sender $BROADCASTER \
  -vvvv
```

The transaction performs:

1. Deploy `CharteredFundImplementation` (regular `new`).
2. Deploy `UpgradeableBeacon` pointing to (1).
3. Deploy `Foundation` implementation (regular `new`).
4. Deploy the deterministic **Foundation proxy** via `ERC1967Factory.deployDeterministicAndCall()` and call `initialize()`.

Only step 4’s proxy address is deterministic across chains.

---

### 2.1 Preview Addresses (dry-run)

```bash
forge script script/2-DeployFoundationKeep.s.sol \
  --fork-url $SEPOLIA_RPC
```

or query the factory directly:

```bash
cast call 0x0000000000006396FF2a80c067f99B3d2Ab4Df24 \
  "predictDeterministicAddress(bytes32)" $PROXY_SALT
```

---

## 3. Upgrade Procedure

Every chartered fund is a **Beacon proxy**.  Upgrading the beacon updates *all*
funds atomically:

```solidity
// called via the hub proxy
Foundation.upgradeCharterImplementation(newImplementation);
```

---

## 4. Vanity Address Examples *(placeholders)*

| Component | Address |
|-----------|---------|
| Foundation implementation | `0x1152…` |
| CharteredFund implementation | `0x11AB…` |
| UpgradeableBeacon | `0xBEEF…` |
| Hub proxy | `0x01152…` |

The proxy shares the `0x01…` prefix because `PROXY_SALT` was mined accordingly.

---

## 5. Local Testing

```bash
forge test --fork-url $SEPOLIA_RPC
```

Use the deterministic addresses inside your tests when needed.

