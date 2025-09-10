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
| `PROXY_SALT` | Foundation hub proxy (raw 32-byte salt; first 21 bytes fixed to `0x00`) | affects all deterministic addresses |
> **Address formula:** The deployed proxy address is  
> `CreateX.computeCreate3Address(keccak256(msg.sender || PROXY_SALT), CREATEX_ADDRESS)`

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
4. Deploy the deterministic **Foundation proxy** via `CreateX.create3AndCall()` (CREATE3) and call `initialize()`.

Only step 4’s proxy address is deterministic across chains.

---

### 2.1 Preview Addresses (dry-run)

_Computation only – no transactions sent_

```bash
forge script script/2-DeployFoundationKeep.s.sol \
  --fork-url $SEPOLIA_RPC
```

---

### Salt safeguarding logic

* **Raw salt layout:** 20 zero bytes + `0x00` sentinel + 11-byte entropy  
* **Guarded salt:** `bytes32 guardedSalt = keccak256(abi.encodePacked(msg.sender, rawSalt));`  
* **Address determinism:** The same `guardedSalt` yields the **same proxy address on every chain** because `CreateX` burns the salt locally after use.  
* **Derivation formula:** `proxy = CreateX.computeCreate3Address(guardedSalt, CREATEX_ADDRESS)`

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

