### 🧠 AiCreditVault
## Solady-based UUPS-upgradeable smart contract system for managing collateralized AI usage credits on-chain.

# 🔍 Overview

AiCreditVault is a smart contract system designed to handle collateralized deposits in ETH or approved ERC20 tokens. It facilitates off-chain crediting of user deposits, tracks credit in "points" (1 point = 1 second of A10G compute), and enforces secure, admin-mediated withdrawal flows. The design emphasizes gas efficiency, predictable accounting, and protocol-controlled asset management.

This contract is designed as an implementation behind an ERC1967 proxy for upgradability.

This contract system allows users to:

- Deposit ETH or approved ERC20 tokens as collateral
- Accumulate off-chain debt for AI generation services
- Withdraw remaining collateral only after debt is reconciled
- Use UUPS upgradeability and ERC1967 proxy deployments
- Optionally farm vanity proxy addresses with CREATE2

The system is composed of:

| Contract            | Purpose                                                                 |
|---------------------|-------------------------------------------------------------------------|
| AiCreditVault       | Core vault logic (collateral, debt, backend authorization)              |
| ERC1967Factory      | Pre-deployed proxy factory from Solady (0x0000...df24)                  |
| UUPSUpgradeable.sol  | Upgrade pattern used for secure logic changes                            |


## 🚀 Deployment Flow
1. Deploy `AiCreditVault` (implementation contract)
2. Use Solady's pre-deployed `ERC1967Factory`:

   ```solidity
   factory.deployDeterministicAndCall(
     implementation,
     admin,
     salt,
     abi.encodeWithSelector(AiCreditVault.initialize.selector, tokens, backend)
   );
   ```

## 🔬 Features
- ✅ ETH & ERC20 deposits (only whitelisted tokens)
- ✅ Off-chain `confirmDebt()` for usage-based accounting
- ✅ Withdrawals locked by unresolved debt
- ✅ `onlyBackend` role gating
- ✅ Solady UUPSUpgradeable logic for lean, gas-efficient upgrades
- ✅ Admin-controlled upgrade and backend management

## 🧱 Storage Design

# Key Mappings

- collateral[user][token] → CollateralRecord struct
- points[user] → int256 (signed integer; positive = credit, negative = debt)
- reconciliation[user][token] → uint256 timestamp of latest confirmed credit
- protocolCollateral[token] → uint256 representing contract-owned assets

Struct: CollateralRecord
```
struct CollateralRecord {
    uint256 amount;       // Amount deposited by user
    uint256 creditedUsd;  // Valuation at time of deposit confirmation (in cents)
    uint256 feeBps;       // Applied withdrawal fee (basis points)
}
```

# Configuration

- acceptedToken[token] → fee in basis points; if 0, token is not accepted
- fixedAcceptedTokens[6] → hardcoded tokens: MS2, CULT, MOG, PEPE, USDT, SPX
- isBackend[address] → offchain-privileged operators (bot, admin)
- withdrawalFeeBps → fallback default fee (e.g., 200 = 2%)
- pointToUsdRate → point pricing in microUSD (e.g., 370 = $0.00037)

## 🔁 Deposit and Credit Lifecycle

User deposits ETH/ERC20

Emits Deposit(user, token, amount)

Bot confirms credit value

Calls confirmCredit(user, token, usdAmount)

Emits CreditConfirmed(user, token, usdAmount)

points[user] updated

reconciliation[user][token] timestamp updated

collateral[user][token] updated (amount, creditedUsd, feeBps)

On Repeated Deposits:

CollateralRecord is overwritten

No per-deposit average/batch history is kept

User assumes accounting risk for blending basis value

## ⚖️ Withdrawal Flow

User signals intent: requestWithdrawal(token, amount) → emits WithdrawalRequested(...)

Bot processes withdrawal:

Calculates refund based on:

credited USD at deposit time

points spent

fee in BPS

Calls withdrawTo(...)

Emits WithdrawReconciled(...)

Contract checks balances and sends ETH or ERC20

Remaining value (after spend/fee) → protocolCollateral[token]

# Withdrawal is Bot-Only:

Prevents abuse of pending collateral

Ensures reconciliation is finalized off-chain

## 🧪 Test Suite (Forge)
1. Deploy logic contract
2. Farm deterministic proxy address
3. Deploy proxy with init data
4. Confirm debt & test withdrawal logic

### Run Tests
```bash
forge test -vvvv
```

### Run Vanity Salt Finder
```bash
forge script script/FarmVanitySalt.s.sol:FarmVanitySalt --sig "run()"
```

## 🛠 Development Commands
```bash
forge build         # compile contracts
forge test          # run tests
forge script        # run deployment or vanity farming scripts
```

💰 Fee Policy

Token-specific withdrawal fees stored in acceptedToken[token]

Higher fees can be assigned to volatile/meme tokens

Fallback withdrawalFeeBps used if token-specific fee unset

Fees collected → protocolCollateral

## 📈 Deposit-Time Price Locking

Credit value locked on confirmation (confirmCredit)

No revaluation at withdrawal

Predictable accounting + reduced manipulation risk

Implications:

Bull Market → protocol can harvest upside

Bear Market → user holds price risk

Fair for all parties; ensures internal accounting integrity

## 🔍 Strategic Liquidation

Bot can preemptively reconcile/spend portions of collateral

Enables protocol to rebalance holdings

Example: liquidate high-performing token balances before price decline

## 🛠 Admin & Execution Functions

confirmCredit(user, token, usdAmount)

withdrawTo(user, token, amount, pointsBurned, usdCreditedAtDeposit)

requestWithdrawal(token, amount)

setAcceptedTokenFee(token, bps)

setWithdrawalFee(uint256)

setPointUsdRate(uint256)

addBackend(addr) / removeBackend(addr)

batchWithdraw(...)

performCalldata(bytes calldata)

performCalldata Safety Logic

Pre-execution snapshot:

For all accepted tokens, record balanceOf(address(this))

Ensure ≥ protocolCollateral[token]

Execute calldata

Post-execution check:

New balanceOf(this) must ≥ updated protocolCollateral[token]

If balance reduced, it must not exceed allowable difference

Update protocolCollateral accordingly

Guarantees user assets are never misappropriated.

## 🔐 Protocol-Owned Assets

Stored separately in protocolCollateral

Represents:

Seized funds from credit spend

Fees collected

Available for admin operations: arbitrage, revenue distribution, liquidity

No user association; no creditedUsd or per-deposit basis needed

## 🛡 Security Model

Users cannot self-withdraw after confirmation

Admin-only reconciliation and withdrawal ensure offchain alignment

Credit system uses points, a stable non-volatile accounting unit

Event log provides full audit trail (confirmations, withdrawals, reconciliation)

points[user] can go negative to support debt-based accounts

## 📚 Resources
- [Solady](https://github.com/vectorized/solady)
- [ERC-1967 Proxy Standard](https://eips.ethereum.org/EIPS/eip-1967)
- [UUPS Pattern](https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies#uups)

## 🧑‍💼 Admin Tips
- Use `ERC1967Factory.adminOf(proxy)` to confirm ownership
- Only the admin passed at proxy creation can upgrade via the factory
- Use `upgrade()` or `upgradeAndCall()` via the factory to change logic safely

## Summary

The AiCreditVault system supports:

Hybrid off-chain/on-chain accounting for AI credit management

Transparent, secure deposits with fixed price basis

Protected admin controls with user safety enforcement

Protocol-level tools for liquidity, arbitrage, and strategic withdrawals