### 🏦 Foundation & CharteredFund: Onchain Custody for Offchain Credit

# Overview

This repository contains the core smart contracts for an onchain accounting system. The contracts are designed as a **hub-and-spoke custody system**: a central `Foundation` contract (the "hub") and optional, user-owned `CharteredFund` contracts (the "spokes").

**Philosophy:**
- **This is not a trustless system.** When users contribute assets, the protocol (a trusted backend service) is in control of those assets.
- The contracts provide a transparent, on-chain source of truth for all custody, credit, and remittance actions. The detailed event logs serve as a robust audit trail for any off-chain systems.
- All core business logic (crediting, escrow, remittances) is initiated by the trusted backend, not by direct user rights over escrowed funds.

# Architecture

The system is composed of two main contracts and three key roles:

| Component         | Purpose                                                                                             |
|-------------------|-----------------------------------------------------------------------------------------------------|
| `Foundation`      | The central hub. It directly holds assets, manages an internal custody ledger, and acts as a factory for `CharteredFund` instances. |
| `CharteredFund`   | An optional, user-owned spoke contract. It provides a dedicated on-chain address for a user's funds, but mirrors all actions to `Foundation` for unified event logging. |
| **Admin**         | The ultimate owner of the system, identified by the ownership of a specific NFT (Milady #598). The Admin can authorize backends and perform emergency actions. |
| **Backend**       | A trusted, authorized address (e.g., a server) that executes the core business logic like locking funds (`commit`) and processing payouts (`remit`). |
| **User**          | Any address that contributes assets to the system. |

# Core Concepts: `userOwned` vs. `escrow`

The heart of the system is the `custody` ledger, which tracks each user's balance for each token. This balance is split into two parts:
- **`userOwned`:** Represents a user's liquid assets within the system. Users can withdraw their `userOwned` balance at any time via `requestRescission()`, even if the system is frozen by the admin.
- **`escrow`:** Represents assets that have been formally committed by the backend for use in the protocol. Users cannot withdraw escrowed funds. Only the backend can move these funds via `remit()`.

# Core Flows

## Standard User Flow (Direct `Foundation` Interaction)
1. **Contribute:** User calls `contribute(token, amount)` or sends ETH directly to `Foundation`.
2. **Custody:** The funds are now in the `Foundation` contract, and the user's `userOwned` balance is credited in the internal ledger.
3. **Commit:** The Backend calls `commit()` to move a user's funds from `userOwned` to `escrow`, signifying the funds are now in use by the protocol.
4. **Remit / Rescind:**
   - The Backend can `remit()` escrowed funds back to the user (e.g., a payout), potentially taking a fee.
   - The User can `requestRescission()` to withdraw their available `userOwned` balance at any time.

## Power User Flow (`CharteredFund` Interaction)
1. **Charter:** The Backend calls `charterFund()` to create a new `CharteredFund` contract owned by a user.
2. **Contribute:** The user deposits assets directly into their personal `CharteredFund` address.
3. **Custody:** The `CharteredFund` holds the assets and maintains its own `custody` ledger, while forwarding event data to `Foundation` for a unified global audit trail.
4. **Commit/Remit:** The Backend interacts with the `CharteredFund` to manage the user's `escrow` balance, just as it would with the `Foundation` contract.

# Asset Handling & CRITICAL Limitations

### Fungible Assets (ETH & ERC20 Tokens)
The system is primarily designed for fungible assets. The `contribute` -> `commit` -> `remit` lifecycle and the `requestRescission` function work reliably for ETH and standard ERC20 tokens.

### Non-Fungible Tokens (NFTs / ERC721) - IMPORTANT CAVEAT
**NFT deposits should be considered a one-way transfer for standard users.**
- The standard user-facing functions (`requestRescission`) and backend functions (`remit`) **WILL FAIL** for NFTs. They are built using `SafeTransferLib`, which is designed for fungible tokens and makes calls that are incompatible with the ERC721 standard.
- There is no standard mechanism for a user or the backend to return an NFT through the normal application flow.

**NFT Management is a manual, admin-level task.** The `Admin` (and `Backend` to a lesser extent) can move any asset, including NFTs, out of the contracts by using the powerful `performCalldata` and `multicall` functions. This is a manual override and is not part of the standard, automated user workflow.

# Security & User Guarantees
- **User funds are under backend control after being committed to escrow.** This is a feature, not a bug. The system provides transparency for a trusted relationship.
- Users can **always** withdraw their uncredited (`userOwned`) balance, even if the backend is frozen by the admin.
- The Admin can enable a global `refund` mode, which allows users to rescind their `escrow` balance. This is an emergency escape hatch for fungible tokens.
- All actions are transparently logged onchain for audit and dispute resolution.

# Technical Details
- **Proxy:** `Foundation` is an ERC1967 UUPS proxy, upgradeable by the NFT owner.
- **CREATE2:** `Foundation` and `CharteredFund` contracts can be deployed at deterministic addresses.
- **Events:**
  - `FundChartered`, `ContributionRecorded`, `CommitmentConfirmed`, `RemittanceProcessed`, `RescissionRequested`, `ContributionRescinded`, `BackendStatusChanged`, `Liquidation`, `OperatorFreeze`, `RefundChanged`, `Donation`.
- **Admin/Utility:**
  - `setBackend`: Authorizes an address to perform backend operations.
  - `setFreeze`: Pauses all backend operations.
  - `setRefund`: Enables the global emergency withdrawal mode.
  - `multicall`: Allows the backend to atomically execute multiple actions.
  - `performCalldata`: Allows the admin to perform arbitrary calls, serving as the ultimate asset management tool.

# For Developers
- See `test/Foundation.t.sol` for a full suite of integration tests covering all flows and limitations.
- Use the event log as the canonical source of truth for all offchain accounting.

# Summary
This system provides operational flexibility and on-chain transparency for credit-based applications. It is not a trustless vault; it is an auditable custody solution built on the principle that the protocol's backend is trusted to manage user assets according to off-chain logic.