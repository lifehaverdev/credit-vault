### 🧠 AiCreditVault
## Solady-based UUPS-upgradeable smart contract system for managing collateralized AI usage credits on-chain.

# 🔍 Overview
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
| Ownable.sol         | Access control for admin/owner roles                                     |

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

## 📚 Resources
- [Solady](https://github.com/vectorized/solady)
- [ERC-1967 Proxy Standard](https://eips.ethereum.org/EIPS/eip-1967)
- [UUPS Pattern](https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies#uups)

## 🧑‍💼 Admin Tips
- Use `ERC1967Factory.adminOf(proxy)` to confirm ownership
- Only the admin passed at proxy creation can upgrade via the factory
- Use `upgrade()` or `upgradeAndCall()` via the factory to change logic safely