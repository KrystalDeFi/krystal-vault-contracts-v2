# SharedVault — Architecture Overview

> **Related docs:** [TrustModel.md](TrustModel.md) · [Audit.md](Audit.md)

## Directory Layout

```
contracts/shared-vault/
├── core/
│   ├── SharedVault.sol             ← Main vault: ERC20 shares + LP position manager
│   ├── SharedVaultFactory.sol      ← Clones pattern vault deployer
│   ├── SharedVaultGateway.sol      ← User UX: swap arbitrary tokens → deposit/withdraw
│   ├── SharedVaultAutomator.sol    ← EIP-712 signed order execution
│   └── SharedConfigManager.sol    ← Protocol-wide whitelists + fee config
├── strategies/
│   ├── SharedStrategyBeacon.sol    ← Upgradeable beacon (hot-swap for all vaults)
│   ├── SharedStrategyProxy.sol     ← Storage-collision-safe delegatecall forwarder
│   ├── SharedV3Strategy.sol        ← Uniswap V3 / Sushi V3
│   ├── SharedV4Strategy.sol        ← Uniswap V4
│   ├── SharedAerodromeStrategy.sol ← Aerodrome CL
│   └── SharedPancakeV4Strategy.sol ← PancakeSwap V4
├── interfaces/                     ← ISharedVault, ISharedStrategy, ISharedCommon, …
└── libraries/                      ← Fees, guards, preview math, proportional exit
```

Per-contract documentation lives in the subdirectories alongside this file.

---

## System Architecture

```
┌──────────────────────────────────────────────────────┐
│               User Entry Points                       │
│  SharedVaultGateway          SharedVaultAutomator     │
│  (swap any token → deposit)  (EIP-712 signed ops)    │
└──────────────┬───────────────────────┬───────────────┘
               ▼                       ▼
      ┌──────────────────────────────────────┐
      │            SharedVault               │
      │  ERC20 shares · tokens[4] · positions│
      └────────────────┬─────────────────────┘
                       │ delegatecall
              ┌────────▼──────────────┐
              │  SharedStrategyProxy  │
              │     (via Beacon)      │
              └────────┬──────────────┘
           ┌───────────┼────────────┬──────────────┐
           ▼           ▼            ▼              ▼
       V3Strategy  V4Strategy  Aerodrome    PancakeV4
                                Strategy     Strategy

SharedConfigManager (singleton)
  ├── whitelistedTargets / Callers / Nfpms / SwapRouters
  ├── platformFeeBasisPoint
  ├── maxPositions (default 20)
  └── minTokenPrecision (default 5)
```

---

## Core Flows

### Deposit — `deposit(amounts[4], slippageBps)`

1. Collect LP fees on all positions (before value snapshot)
2. Snapshot total vault value (idle balances + LP positions)
3. Transfer tokens in (ETH auto-wrapped to WETH)
4. `depositProportional()` to top up each existing LP position
5. Mint shares proportional to value contributed
   - First depositor: `INITIAL_SHARES = 10e18` (decouples from token decimals)

### Withdraw — `withdraw(shares, minAmounts[4], unwrap)`

1. Burn shares
2. Collect LP fees on all positions
3. `exitProportional(shares / totalSupply)` on each position
4. Accumulate idle balances + exited LP amounts
5. Optionally unwrap WETH → ETH
6. Transfer out with per-token `minAmounts` guards (sandwich protection)

### Execute — `execute(Action[])` (owner / admin / whitelisted caller)

| `CallType` | Target | Returns |
|---|---|---|
| `DELEGATECALL` | Whitelisted strategy | `PositionChange[]` → tracked |
| `CALL` | Whitelisted swap router | Token swap, `minAmountOut` enforced (no floor — caller may set 0; see [TrustModel.md](TrustModel.md)) |
| `CALL_WITH_POSITIONS` | Trusted strategy impl (direct call) | `PositionChange[]` → tracked |

---

## Strategy Upgrade Pattern

- `SharedStrategyProxy` holds no storage — all state lives in the **vault's** storage context via `delegatecall`
- The proxy reads its implementation from an **immutable beacon address** at construction time
- The beacon owner (protocol multisig) can `setImplementation()` → **all vaults upgrade simultaneously**
- This avoids standard transparent/UUPS proxy storage-collision risk because the proxy itself is only ever delegatecalled into, never called directly for state

---

## Position Tracking

```solidity
struct Position {
  address strategy;  // proxy to delegatecall on exit
  address nfpm;      // NFT position manager
  uint256 tokenId;   // Position NFT ID
  address token0;    // Pool token0 (must be a vault token)
  address token1;    // Pool token1 (must be a vault token)
}
```

- Stored in `positions[]` array
- O(1) lookup: `positionIndex[keccak256(nfpm, tokenId)]` → `index + 1` (0 = not tracked)
- Auto-untracked when fully exited
- `dropPosition` (owner/operator): forcibly untrack, transfer NFT to operator
- `recoverPosition` (operator): re-add a previously dropped position

---

## Fee Model

Two-tier fee applied during `collectFees()` and `exitProportional()`:

| Fee | Recipient | Mutability |
|-----|-----------|------------|
| Platform fee | `configManager.feeRecipient` | Set by protocol owner |
| Vault owner fee | `vaultOwner` | **Locked at vault initialization** |
| Gas fee | Executor (per operation) | Set per strategy call |

Fees are applied sequentially via `SharedStrategyFees.applyFees()`, each clamped to the remaining amount. Combined platform + vault owner fee is enforced ≤ 10,000 bps in `SharedStrategyFeeConfig`.

---

## Roles & Access Control

| Role | Powers |
|------|--------|
| `vaultOwner` | `execute`, manage admins, pause vault, `dropPosition`, `transferOwnership` |
| `admin` | `execute` only |
| `whitelistedCaller` (ConfigManager) | `execute` (used by automator bots) |
| `operator` | Emergency sweeps, `recoverPosition`, `dropPosition` |
| Beacon owner (protocol multisig) | Hot-swap strategy implementation for **all vaults** |
| ConfigManager owner | All whitelists, fee rates, `maxPositions`, global pause |

`vaultOwnerFeeBasisPoint` is the only owner-controlled parameter permanently locked after `initialize()`.

---

## Security Properties

| Property | Mechanism |
|----------|-----------|
| Dust dilution attack prevention | `minTokenPrecision`: min deposit = `10^(decimals - precision)` |
| Swap aggregator failures | Same dust floor ensures slices are large enough to route |
| Sandwich attacks on withdraw | Per-token `minAmounts[4]` enforced after exit |
| Unauthorized delegatecall | Only `configManager.whitelistedTargets` may be delegatecalled (checked at position creation; not re-checked on existing positions — see [Audit.md H-01](Audit.md)) |
| Position token validation | `getPositionTokens()` checked against vault token set |
| Fee-on-transfer tokens | Share math uses actual balance deltas, not requested amounts |
| Reentrancy | `ReentrancyGuardUpgradeable` on deposit/withdraw |

---

## Factory & Deployment

`SharedVaultFactory.createVault()` uses `Clones.cloneDeterministic` with salt `keccak256(name, creator, "shared-1.0")` — prevents duplicate vault names per creator. An optional array of initial `execute()` actions can be passed; the factory acts as temporary vault owner during creation, then transfers ownership to the intended owner.
