### CreditVault: Onchain Payment Accumulator with Referral Registry

# Overview

A single UUPS-upgradeable smart contract that accepts ETH and ERC20 payments, splits a configurable referral cut to registered referrers, and accumulates the remainder for protocol withdrawal.

**Design principles:**
- **All sales final.** No escrow, no commit/remit cycle, no rescission.
- **Immediate referral distribution.** Referral cuts are pushed to the referrer on every payment.
- **Pull pattern for protocol revenue.** Accumulated protocol balance is withdrawn by the owner via `withdrawProtocol()`.
- **Single contract.** Replaces the previous multi-contract Foundation/CharteredFund system (archived in `archive/`).

# Architecture

| Component | Purpose |
|---|---|
| `CreditVault` | Accepts payments, manages referral registry, accumulates protocol revenue. |
| **Owner** | Admin (OwnableRoles). Sets referral rates, withdraws protocol funds, upgrades proxy. |
| **Referrer** | Self-registered via `register(name)`. Receives a cut of payments that reference their key. |
| **Payer** | Any address that sends ETH or ERC20 tokens, optionally citing a referral key. |

# Payment Flow

1. **Pay:** Payer calls `payETH(referralKey)`, `pay(token, amount, referralKey)`, or sends ETH to `receive()`.
2. **Split:** If a valid `referralKey` is provided, the referrer's cut (default 5%, configurable per-referrer up to 50%) is pushed immediately.
3. **Accumulate:** The protocol's share stays in the contract.
4. **Withdraw:** Owner calls `withdrawProtocol(token, to, amount)` to pull accumulated revenue.

# Referral Registry

Referrers self-register with a string name. Registration is permissionless and first-come-first-served.

| Function | Description |
|---|---|
| `register(name)` | Claim a name. Sets the caller as both owner and payout address. |
| `setAddress(key, to)` | Change the payout address (owner only). |
| `transferName(key, newOwner)` | Transfer name ownership (owner only). |

Admin can override per-referrer rates via `setReferralBps(key, bps)` or change the global default via `setDefaultBps(bps)`.

# NFT Handling

The vault accepts ERC721, ERC1155, and ERC1155 batch transfers. These are held in the contract and can be withdrawn by the owner via `withdrawNFT()` or `withdrawERC1155()`. No internal ledger is maintained for NFTs.

# Admin Functions

| Function | Description |
|---|---|
| `setDefaultBps(bps)` | Set default referral cut (max 50%). |
| `setReferralBps(key, bps)` | Set custom rate for a specific referrer. |
| `withdrawProtocol(token, to, amount)` | Withdraw accumulated ETH or ERC20. |
| `withdrawNFT(token, tokenId, to)` | Withdraw an ERC721. |
| `withdrawERC1155(token, tokenId, amount, to)` | Withdraw an ERC1155. |
| `multicall(data[])` | Batch multiple admin calls in one transaction. |

# Deployment

Deployed deterministically via CreateX CREATE3. Same address on every chain with the same salt.

```bash
PROXY_SALT=<hex32> OWNER=<address> \
forge script script/DeployCreditVault.s.sol \
  --fork-url $RPC_URL --broadcast --account <keystore-name> -vvvv
```

# Technical Details

- **Proxy:** ERC1967 UUPS, upgradeable by owner.
- **Dependencies:** Solady (OwnableRoles, UUPSUpgradeable, Initializable, ReentrancyGuard, SafeTransferLib).
- **Deterministic addresses:** CreateX CREATE3 factory (`0xba5E…ba5Ed`).
- **Reentrancy:** All payment functions are `nonReentrant`. If an ETH referral push reverts, the cut is skipped (protocol keeps it).

# V1 Archive

The previous Foundation/CharteredFund hub-and-spoke custody system is preserved in `archive/` for reference. The V1 vault has been drained and is no longer active.
