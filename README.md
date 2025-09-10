### 🏦 Foundation & CharteredFund: Onchain Custody for Offchain Credit

# Overview

This repository contains the core smart contracts for an onchain accounting system. The contracts are designed as a **hub-and-spoke custody system**: a central `Foundation` contract (the "hub") and optional, user-owned `CharteredFund` contracts (the "spokes").

**Philosophy:**
- **This is not a trustless system.** When users contribute assets, the protocol (a trusted backend service) is in control of those assets.
- The contracts provide a transparent, on-chain source of truth for all custody, credit, and remittance actions. The detailed event logs serve as a robust audit trail for any off-chain systems.
- All core business logic (crediting, escrow, remittances) is initiated by the trusted marshal, not by direct user rights over escrowed funds.

# Architecture

The system is composed of two main contracts and three key roles:

| Component         | Purpose                                                                                             |
|-------------------|-----------------------------------------------------------------------------------------------------|
| `Foundation`      | The central hub. It directly holds assets, manages an internal custody ledger, and acts as a factory for `CharteredFund` instances. |
| `CharteredFund`   | An optional, user-owned spoke contract. It provides a dedicated on-chain address for a user's funds, but mirrors all actions to `Foundation` for unified event logging. |
| **Admin**         | The ultimate owner of the system, identified by the ownership of a specific NFT (Milady #598). The Admin can authorize marshals and perform emergency actions. |
| **Marshal**       | A trusted, authorized address (e.g., a server) that executes the core business logic like locking funds (`commit`) and processing payouts (`remit`). |
| **User**          | Any address that contributes assets to the system. |

# Core Concepts: `userOwned` vs. `escrow`

The heart of the system is the `custody` ledger, which tracks each user's balance for each token. This balance is split into two parts:
- **`userOwned`:** Represents a user's liquid assets within the system. Users can withdraw their `userOwned` balance at any time via `requestRescission()`, even if the system is frozen by the admin.
- **`escrow`:** Represents assets that have been formally committed by the marshal for use in the protocol. Users cannot withdraw escrowed funds. Only the marshal can move these funds via `remit()`.

# Core Flows

## Standard User Flow (Direct `Foundation` Interaction)
1. **Contribute:** User calls `contribute(token, amount)` or sends ETH directly to `Foundation`.
2. **Custody:** The funds are now in the `Foundation` contract, and the user's `userOwned` balance is credited in the internal ledger.
3. **Commit:** The marshal calls `commit()` to move a user's funds from `userOwned` to `escrow`, signifying the funds are now in use by the protocol.
4. **Remit / Rescind:**
   - The marshal can `remit()` escrowed funds back to the user (e.g., a payout), potentially taking a fee.
   - The User can `requestRescission()` to withdraw their available `userOwned` balance at any time.

## Power User Flow (`CharteredFund` Interaction)
1. **Charter:** The marshal calls `charterFund()` to create a new `CharteredFund` contract owned by a user.
2. **Contribute:** The user deposits assets directly into their personal `CharteredFund` address.
3. **Custody:** The `CharteredFund` holds the assets and maintains its own `custody` ledger, while forwarding event data to `Foundation` for a unified global audit trail.
4. **Commit/Remit:** The marshal interacts with the `CharteredFund` to manage the user's `escrow` balance, just as it would with the `Foundation` contract.

# Asset Handling & CRITICAL Limitations

### Fungible Assets (ETH & ERC20 Tokens)
The system is primarily designed for fungible assets. The `contribute` -> `commit` -> `remit` lifecycle and the `requestRescission` function work reliably for ETH and standard ERC20 tokens.

### Non-Fungible Tokens (NFTs / ERC721) - IMPORTANT CAVEAT
**NFT deposits should be considered a one-way transfer for standard users.**
- The standard user-facing functions (`requestRescission`) and marshal functions (`remit`) **WILL FAIL** for NFTs. They are built using `SafeTransferLib`, which is designed for fungible tokens and makes calls that are incompatible with the ERC721 standard.
- There is no standard mechanism for a user or the marshal to return an NFT through the normal application flow.

**NFT Management is a manual, admin-level task.** The `Admin` (and `marshal` to a lesser extent) can move any asset, including NFTs, out of the contracts by using the powerful `performCalldata` and `multicall` functions. This is a manual override and is not part of the standard, automated user workflow.

# Security & User Guarantees
- **User funds are under marshal control after being committed to escrow.** This is a feature, not a bug. The system provides transparency for a trusted relationship.
- Users can **always** withdraw their uncredited (`userOwned`) balance, even if the marshal is frozen by the admin.
- The Admin can enable a global `refund` mode, which allows users to rescind their `escrow` balance. This is an emergency escape hatch for fungible tokens.
- All actions are transparently logged onchain for audit and dispute resolution.

## Deterministic Deployment via CreateX (2-step flow)

- **Scope:** The `Foundation` proxy, beacon, and all implementation contracts are deployed deterministically with **CREATE3** through the canonical CreateX factory (`0xba5E…ba5Ed`).  Locking the salts guarantees the **same addresses on every chain**—no extra contracts to deploy.  
- **Inputs:** A single vanity-mined `PROXY_SALT` (raw 32-byte value) plus `OWNER_NFT` & `OWNER_TOKEN_ID`. See [script/README.md](script/README.md) for the full environment variable table.

### 1. Mine your vanity salt

```bash
forge script script/1-MineFoundationProxySalt.s.sol \
  --fork-url $RPC_URL
```

The script brute-forces numeric salts until it finds one whose resulting proxy address matches your desired hex prefix.  Once you spot a match, export it as `PROXY_SALT`.

### 2. One-shot deployment

```bash
PROXY_SALT=<hex32> \
OWNER_NFT=<address> \
OWNER_TOKEN_ID=<uint256> \
forge script script/2-DeployFoundationKeep.s.sol \
  --fork-url $RPC_URL \
  --broadcast \
  --sender $BROADCASTER \
  -vvvv
```

`2-DeployFoundationKeep.s.sol` performs the following inside **one transaction**:

1. Deploy `CharteredFundImplementation` (CREATE3 via CreateX).
2. Deploy `UpgradeableBeacon`, pointing to (1).
3. Deploy `Foundation` implementation (CREATE3 via CreateX).
4. Call `CreateX.create3AndCall()` to deploy the **deterministic hub proxy** and run `initialize()` with your chosen owner NFT.

Because **every** component is created through CREATE3, the addresses are identical across chains as long as the salts remain unchanged.

#### Preview addresses (dry-run)

You can preview all deterministic addresses without broadcasting any transaction:

```bash
forge script script/2-DeployFoundationKeep.s.sol \
  --fork-url $RPC_URL
```

---

### Best Practices / Golden Rules

• Commit the chosen `PROXY_SALT` to the repo (or env sample) so it never changes accidentally.  
• A “virgin” deployer wallet is **no longer required**—addresses depend solely on the salts and not on wallet nonces.  
• No extra contracts to deploy – the canonical CreateX factory (`0xba5E…ba5Ed`) is already live on all major chains.  
• Keep compiler version and optimisation settings locked—bytecode drift breaks predictability for the init-code hash.

---

# Technical Details
- **Proxy:** `Foundation` is an ERC1967 UUPS proxy, upgradeable by the NFT owner.
- **CREATE3:** All components are deployed deterministically via CreateX, sharing the same addresses across chains.
- **Events:**
  - `FundChartered`, `