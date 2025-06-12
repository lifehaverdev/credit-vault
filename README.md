### 🏦 VaultRoot & VaultAccount: Onchain Custody for Offchain AI Credit

# Overview

This repo contains the core smart contracts for our AI application's onchain accounting system. The contracts are designed as a **hub-and-spoke custody system**: a central `VaultRoot` contract (the "wheel") and optional, user-owned `VaultAccount` contracts (the "spokes").

**Philosophy:**
- These contracts are not a trustless vault. When users deposit, the protocol (backend/operator) is in full control of the funds.
- The contracts provide transparent, onchain state and event logs for all custody, credit, and withdrawal actions, serving as a robust audit trail for offchain accounting.
- All crediting, escrow, and withdrawal logic is enforced by the backend/operator, not by user rights.

# Architecture

| Contract       | Purpose                                                                                             |
|----------------|-----------------------------------------------------------------------------------------------------|
| `VaultRoot`    | The central hub. Receives user deposits, manages custody, and acts as a factory/controller for `VaultAccount` instances. |
| `VaultAccount` | Optional, user-owned spoke contract for power users/teams who want a dedicated custody/accounting environment. |

## Deployment
- `VaultRoot` is deployed as an ERC1967 UUPS proxy, ideally at a vanity address using CREATE2 for easy discovery and trust minimization.
- `VaultAccount` contracts are deployed by the backend via `VaultRoot.createVaultAccount(owner, salt)`, using CREATE2 for deterministic addresses.

# Core Flows

## Standard User Flow (Direct `VaultRoot` Interaction)
1. **Deposit:** User calls `deposit(token, amount)` or sends ETH to `VaultRoot`.
2. **Custody:** Funds are held in the contract, tracked in a packed `custody` mapping (`userOwned` and `escrow` balances).
3. **Credit:** Backend/operator calls `confirmCredit` to move user funds from `userOwned` to `escrow` (credit granted for offchain use).
4. **Withdrawal:** Backend/operator calls `withdrawTo` to send funds (minus any fee) to the user, or user can withdraw their uncredited `userOwned` balance at any time.

## Power User Flow (`VaultAccount` Interaction)
1. **Account Creation:** Backend creates a `VaultAccount` for a user/team via `VaultRoot.createVaultAccount`.
2. **Deposit:** User/team deposits into their `VaultAccount` (ETH or ERC20).
3. **Custody:** Funds are tracked in the `VaultAccount`'s own `custody` mapping. All actions are mirrored to `VaultRoot` for unified event logging.
4. **Credit/Withdrawal:** Backend manages credit and withdrawals via the `VaultAccount`, which in turn notifies `VaultRoot` for event consistency.

# Custody & State
- **custody mapping:** Both `VaultRoot` and each `VaultAccount` use a packed `bytes32` mapping: lower 128 bits = `userOwned` (withdrawable by user if not credited), upper 128 bits = `escrow` (credited, only withdrawable by backend).
- **Events:** All deposits, credits, withdrawals, and backend actions emit detailed events for offchain indexing and audit.

# Operator/Backend Role
- Only addresses authorized as `backend` can credit, move, or withdraw escrowed funds.
- The owner (Milady NFT #598 holder) can add/remove backends and freeze all backend operations (`setFreeze`).
- The backend is expected to run offchain logic for crediting, reconciliation, and user withdrawal processing.

# Security & User Guarantees
- **User funds are always under backend/operator control after deposit.**
- Users can withdraw their uncredited (`userOwned`) balance at any time, even if the backend is frozen.
- Once credited (moved to `escrow`), only the backend can process withdrawals.
- All actions are transparently logged onchain for audit and dispute resolution.

# Technical Details
- **Proxy:** `VaultRoot` is an ERC1967 UUPS proxy, upgradeable by the NFT owner.
- **CREATE2:** Both `VaultRoot` and `VaultAccount` can be deployed at deterministic addresses for trust minimization and offchain address prediction.
- **Packed Storage:** All balances are packed for gas efficiency.
- **Events:**
  - `DepositRecorded`, `CreditConfirmed`, `WithdrawalProcessed`, `UserWithdrawal`, `VaultAccountCreated`, `BackendStatusChanged`, `OperatorFreeze`, `Liquidation`.
- **Admin/Utility:**
  - `setBackend`, `setFreeze`, `multicall`, `performCalldata` (arbitrary call by owner).

# Example Event Flow
1. User deposits 1 ETH to `VaultRoot`.
2. `DepositRecorded` event emitted.
3. Backend calls `confirmCredit`, moving 1 ETH to `escrow` for offchain use. `CreditConfirmed` event emitted.
4. Later, backend calls `withdrawTo` to send 0.9 ETH to user (0.1 ETH fee). `WithdrawalProcessed` event emitted.

# For Developers
- See `test/Vault.t.sol` for a full suite of integration tests covering all flows.
- Use the event log as the canonical source of truth for all offchain accounting and dispute resolution.

# Development
```bash
forge build         # compile contracts
forge test          # run tests
forge script        # run deployment or vanity farming scripts
```

# Resources
- [Solady](https://github.com/vectorized/solady) for gas-optimized utilities and base contracts.
- [ERC-1967 Proxy Standard](https://eips.ethereum.org/EIPS/eip-1967) for UUPS upgradeability.
- [CREATE2 Opcode](https://eips.ethereum.org/EIPS/eip-1014) for deterministic address generation.

# Summary
This system is designed for maximum transparency and operational flexibility for offchain AI credit management. It is not a trustless vault: the protocol is always in control, but all actions are onchain and auditable.