# Shared Vault — Current Implementation

> **This is current-state documentation, not a design plan.** It reflects the contracts as deployed on `feat/shared-vault`. For the audit findings that drove the most recent changes, see `shared-vault-audit-report.md`.

## Overview

The Shared Vault is a multi-depositor ERC20-share vault that holds up to 4 ERC20 tokens simultaneously and manages multiple Uniswap-V3-family LP positions. Shares represent proportional ownership of idle tokens plus all active LP positions. Unlike the public vault, there is no single "principal token" — deposits and withdrawals always involve the current proportional ratio of all four configured tokens.

### Position vs public/private vault

| Aspect | Public Vault | Private Vault | **Shared Vault** |
|---|---|---|---|
| Depositors | Many | One (owner) | Many |
| Shares | ERC20 | None | ERC20 |
| Principal token | Single | None (any) | None (multi-token) |
| LP management | Validated strategies | Raw multicall | Validated strategies |
| Swap mechanism | OptimalSwapper | Aggregator | Aggregator (via Gateway) |
| Range constraints | ConfigManager | Owner-bounded | Whitelisted strategies only |

---

## Architecture

```
                        ┌──────────────────────────┐
                        │   SharedVaultGateway     │  ← primary user entry point
                        │   (swap-aggregator UX)   │     uses Krystal API calldata
                        └──────────┬───────────────┘
                                   │ deposit / withdraw
                                   ▼
┌────────────────────────────────────────────────────────────────┐
│                         SharedVault                            │
│                                                                │
│  • Up to 4 ERC20 tokens; ERC20 shares (18 decimals)            │
│  • INITIAL_SHARES = 10e18 on first deposit                     │
│  • Idle-snapshot withdraw + LP exit (no double-dilution)       │
│  • Pre-collect fees before idle snapshot (fair distribution)   │
│  • Position tracking with auto-untrack on full exit            │
│  • EIP-1271 (vault acts as smart-wallet signer)                │
│  • FOT-safe: shares from actual delta, not requested amount    │
└─┬───────────────────────────────────────────────────────────┬──┘
  │ delegatecall (LP ops, exit, deposit-proportional)         │
  ▼                                                           ▼
┌──────────────────────────────┐                ┌────────────────────────┐
│   SharedStrategyProxy        │                │  SharedConfigManager   │
│   immutable beacon ref       │                │  • whitelistedTargets  │
│   storage-collision-safe     │                │  • whitelistedCallers  │
└──────────┬───────────────────┘                │  • whitelistedNfpms    │
           │ delegatecall                       │  • whitelistedSwapRouters│
           ▼                                    │  • platformFeeBasisPoint│
┌──────────────────────────────┐                │  • maxPositions (20)   │
│   SharedStrategyBeacon       │                │  • minTokenPrecision(5)│
│   stores impl address        │                └────────────────────────┘
│   protocol-multisig-owned    │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│   StrategyImpl               │  SharedV3Strategy / SharedV4Strategy /
│   (V3 / V4 / Aerodrome)      │  SharedAerodromeStrategy
│                              │
│  • execute(bytes data)       │
│  • exitProportional          │
│  • depositProportional       │
│  • collectFees               │
│  • getPositionAmounts/...    │
└──────────┬───────────────────┘
           │ LpFeeTaker.takeFees (V3/Aerodrome)
           ▼
┌──────────────────────────────┐
│   LpFeeTaker (external)      │  Routes platform + vault-owner fees
│   contracts/public-vault/    │  to feeRecipient & vaultOwner
└──────────────────────────────┘
```

Aux contract: **SharedVaultAutomator** — operator-driven batch execution with EIP-712 + EIP-1271 signing.

---

## Trust Model

| Role | Granted by | Powers |
|---|---|---|
| **vaultOwner** | Vault creator / `transferOwnership` | `execute`, `dropPosition`, manage admins, per-vault pause, set fee bps (LOCKED at init only) |
| **admin** | `vaultOwner.grantAdminRole` | `execute` only |
| **operator** | Set at `initialize`, **fixed** (no setter) | `sweep*`, `recoverPosition`, `dropPosition` (force-drop escape hatch) |
| **whitelisted caller** | `ConfigManager.setWhitelistCallers` | `execute` (used by automator) |
| **depositor** | Anyone | `deposit`, `withdraw` |
| **factory** | Permanent (set at init) | `execute` (creation-time strategy init only — temporary owner during factory `createVault` with actions) |
| **beacon owner** | Beacon constructor | Hot-swap strategy implementation for **every** vault using that strategy |
| **configManager owner** | ConfigManager `initialize` | Manage four whitelists, set fees, set maxPositions, set minTokenPrecision, global pause |

### Custody asymmetries to note

1. **`dropPosition` transfers NFT to operator** (when operator is set). Vault owner cannot retrieve the NFT directly afterward — only the operator can via `recoverPosition` or `sweepERC721`. If no operator is set, the NFT stays in the vault but cannot be moved out (sweep is operator-only).
2. **Operator can also call `dropPosition`** — emergency escape hatch added in response to W-5/W-10. Lets the protocol unbrick deposits/withdrawals when a strategy or NFPM breaks and the vault owner is unavailable.
3. **`vaultOwnerFeeBasisPoint` is locked at vault initialization.** No setter. Depositors can rely on the value seen at vault creation.
4. **`platformFeeBasisPoint` can be raised by the protocol** to squeeze the vault-owner share (`SharedStrategyFeeConfig` silently clamps `vaultOwnerBps` down so the combined fee never exceeds 10000).

---

## File Structure

```
contracts/shared-vault/
  interfaces/
    ISharedCommon.sol              — CallType enum, all shared errors
    ISharedVault.sol               — Position/Action structs, all events, lock-at-init vaultOwnerFeeBasisPoint
    ISharedConfigManager.sol       — Four whitelists, platformFee, maxPositions, minTokenPrecision
    ISharedStrategy.sol            — execute / exitProportional / depositProportional / collectFees /
                                     getPositionAmounts / getPositionPrincipalAmounts / getPositionTokens
    ISharedVaultFactory.sol        — Two createVault overloads (both take vaultOwnerFeeBasisPoint)
    ISharedVaultAutomator.sol      — executeWithAgentAllowance, executeWithUserOrder, cancelOrder
  core/
    SharedVault.sol                — Main vault contract
    SharedVaultGateway.sol         — Aggregator-fronted deposit/withdraw UX layer
    SharedVaultFactory.sol         — Clones-based vault deployer
    SharedConfigManager.sol        — Protocol-level config + whitelists
    SharedVaultAutomator.sol       — EIP-712 signed batch execution
  strategies/
    SharedStrategyBeacon.sol       — Per-strategy-type beacon (Ownable)
    SharedStrategyProxy.sol        — Storage-collision-safe forwarder (beacon = immutable)
    SharedV3Strategy.sol           — Uniswap V3 / Pancake V3 / Sushi V3 LP ops
    SharedV4Strategy.sol           — Uniswap V4 LP ops (Permit2 flow)
    SharedAerodromeStrategy.sol    — Aerodrome CL LP ops (tickSpacing-based pool lookup)
  libraries/
    SharedNfpmProportionalExit.sol — V3-family proportional exit (collect → fees → decrease → collect)
    SharedStrategyFeeConfig.sol    — FeeConfig builder with platform/owner-fee clamp logic
    SharedStrategyGuards.sol       — `requireWhitelistedNfpm` helper
```

---

## SharedConfigManager

**Storage:**

```solidity
mapping(address => bool) public whitelistedTargets;       // strategy proxies (DELEGATECALL + CALL_WITH_POSITIONS)
mapping(address => bool) public whitelistedCallers;       // automator address(es)
mapping(address => bool) public whitelistedNfpms;         // allowed NFT position managers
mapping(address => bool) public whitelistedSwapRouters;   // allowed swap aggregators (CALL path only)
bool   public isVaultPaused;                              // global protocol pause
address public feeRecipient;
uint16 public platformFeeBasisPoint;                      // ≤ 10000, applied to LP perf collections
uint16 public maxPositions;                               // default 20
uint8  public minTokenPrecision;                          // default 5 → 10^(decimals-5) per-token floor
```

`setMinTokenPrecision(0)` disables the per-token floor (ceiling rounding in `_subsequentDepositTransfers` still prevents the classic deposit-dilution attack).

`setPlatformFeeBasisPoint(bps)` reverts on `bps > 10000`. The fee is applied to collected LP fees only — never to principal.

---

## SharedVault — Behavior

### Initialization

```solidity
function initialize(
  string  name,
  address[4] _tokens,
  uint256[4] initialAmounts,
  address _owner,
  address _operator,                   // fixed; no post-deploy setter
  address _configManager,
  address _weth,
  uint16  _vaultOwnerFeeBasisPoint     // LOCKED at init; no setter
) external initializer
```

`_tokens` may have address(0) gaps (e.g., 2-token vault stored in slots 0,1 with slots 2,3 empty). Each non-zero token is probed for `decimals()` — tokens that don't implement IERC20Metadata are rejected at init to prevent later bricking. At least 2 distinct non-zero tokens are required.

INITIAL_SHARES (10e18) is minted to `_owner` if any `initialAmounts[i] > 0`.

### Deposit Flow

```
1. Snapshot currentTotalSupply
2. Snapshot totalBalancesBefore (idle + LP via strategy.getPositionAmounts)
3. Snapshot idleBeforePull (BEFORE wrap, so deltas capture both wrap and pull)
4. Validate WETH path: msg.value == amounts[wethIndex] if msg.value > 0

5. Compute transferAmounts:
   - First deposit (totalSupply == 0): transferAmounts = amounts (no scaling)
   - Subsequent: transferAmounts[i] = max(ceiling(sharesOut * totalBalances[i] / totalSupply),
                                          10^max(0, decimals - minTokenPrecision))
                 where sharesOut = min over i of mulDiv(amounts[i], totalSupply, totalBalances[i])
                 (binding-token rule, floor division — depositor over-pays for sub-1-wei slices)

6. Wrap msg.value into WETH for slot[wethIndex]; refund excess ETH AFTER mint (reentrancy guard)

7. Pull transferAmounts[i] from caller for each non-WETH slot via safeTransferFrom

8. Measure actualPulled[i] = balanceOf(this) - idleBeforePull[i]
   (FOT-safe: depositor is credited for what actually arrived, not what was requested)

9. If totalSupply > 0 and positions.length > 0:
     For each tracked position, top up proportionally:
       toAdd0 = mulDiv(actualPulled[token0Idx], principal0, totalBalances[token0Idx])
       toAdd1 = mulDiv(actualPulled[token1Idx], principal1, totalBalances[token1Idx])
       (uses `getPositionPrincipalAmounts`, NOT `getPositionAmounts`, so increaseLiquidity ratio
        matches the range — uncollected fees are NOT mixed into the top-up amounts.)
       if toAdd0 > 0 or toAdd1 > 0:
         delegatecall strategy.depositProportional(nfpm, tokenId, toAdd0, toAdd1, slippageBps)

10. shares:
    - First deposit: INITIAL_SHARES (10e18)
    - Subsequent: min over i where actualPulled[i] > 0 of
                  mulDiv(balancesAfter[i] - balancesBefore[i], totalSupply, balancesBefore[i])

11. _mint(msg.sender, shares); refund excess ETH; emit VaultDeposit(actualPulled, shares)
```

**Why measure actualPulled?** Fee-on-transfer and non-standard ERC20 tokens may transfer less than requested. Without measurement, the vault would credit the depositor based on requested amounts → over-mint shares → dilute existing holders. The measurement step also makes the deposit safe for any future ERC20 quirk that affects the transfer delta.

### Withdrawal Flow

```
1. _burn(caller, shares)
2. For each tracked position:
     delegatecall strategy.collectFees(nfpm, tokenId, vaultOwnerFeeBasisPoint)
     // Collects accumulated LP fees into idle, takes platform + owner cut via LpFeeTaker.
     // Reverts the entire withdrawal on failure — a silent collect failure followed by
     // exitProportional would let the current withdrawer sweep all accrued fees.

3. Snapshot idleBefore AFTER collectFees (so accrued fees are distributed proportionally).

4. For each tracked position (swap-with-last on full exit):
     delegatecall strategy.exitProportional(nfpm, tokenId, shares, totalSupply_before_burn, 0, 0,
                                            vaultOwnerFeeBasisPoint)
     // Per-position minAmount0/1 are zero — one tight position must not DoS the whole withdrawal.
     // Aggregate slippage is enforced by minAmounts[] passed to withdraw().

5. For each token:
     lpExitReturn = balanceOf(this) - idleBefore[i]
     amounts[i] = mulDiv(shares, idleBefore[i], totalSupply_before_burn) + lpExitReturn
     // Idle proportion + full LP return = no double-dilution.
     require(amounts[i] >= minAmounts[i], InsufficientOutput())
     if unwrap == true and tokens[i] == weth: WETH.withdraw → send raw ETH to caller
     else: safeTransfer to caller
```

### `previewWithdraw` returns NET amounts

Returns the proportional share of `idle + LP principal + (1 − feeRate) × uncollected LP fees`, where `feeRate` is `platformFeeBasisPoint + vaultOwnerFeeBasisPoint` (with the same silent clamp as `SharedStrategyFeeConfig.performanceFeeConfig`). Principal exits carry no perf/platform fee. Callers should still pad for AMM slippage at exit time.

### `execute(Action[])` — three CallTypes

| CallType | Target whitelist | Behavior |
|---|---|---|
| `DELEGATECALL` | `isWhitelistedTarget` | `delegatecall(strategy.execute(data))`; result decoded as `PositionChange[]`. New positions validated: `isVaultToken[token0/token1]` + `getPositionTokens` canonical check + `IERC721(nfpm).ownerOf == address(this)` |
| `CALL` | `isWhitelistedSwapRouter` | Decodes `(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata)`. Validates `isVaultToken[tokenIn/tokenOut]`, approves `tokenIn` for exact `amountIn`, calls router with `swapCalldata`, resets approval, checks output delta ≥ minAmountOut |
| `CALL_WITH_POSITIONS` | `isWhitelistedTarget` | Raw `call(data)` whose return is decoded as `PositionChange[]`. New positions get the SAME defense-in-depth checks as DELEGATECALL plus a `getPositionAmounts` probe (must not revert and must return 64 bytes) |

### Position lifecycle

- **Add** — via strategy returning `PositionChange(isAdd=true)`. Required: `_msgSender()` authorized; `isWhitelistedTarget(strategy)`; `isWhitelistedNfpm(nfpm)`; `isVaultToken[token0/token1]`; canonical pair matches `getPositionTokens(nfpm, tokenId)`; vault owns NFT (`ownerOf == address(this)`); `positions.length < maxPositions`.
- **Remove (full exit)** — via strategy returning `PositionChange(isAdd=false)` during `execute` or `exitProportional`. Verified via `_verifyPositionExit`: if vault still owns NFT, strategy must report zero `getPositionAmounts`.
- **Drop (emergency)** — `dropPosition(nfpm, tokenId)` callable by `vaultOwner` OR `operator`. Removes from tracking; transfers NFT to operator if set (custody asymmetry — operator returns it via `recoverPosition`).
- **Recover** — `recoverPosition(nfpm, tokenId, strategy, token0, token1)` callable by `operator`. Validates: NFPM whitelisted, tokens are vault tokens, strategy whitelisted, canonical pair matches. Pulls NFT back via `transferFrom(operator → vault)` (operator must have approved vault on the NFPM). Re-adds to tracking.

### EIP-1271

`SharedVault.isValidSignature(hash, sig)` returns `MAGIC_VALUE` if `SignatureChecker.isValidSignatureNow(vaultOwner, hash, sig)`. Supports:
- Vault owner is an EOA → ECDSA validation.
- Vault owner is a smart wallet → EIP-1271 cascade (validates against the smart wallet's `isValidSignature`).

The vault itself can therefore act as a smart-wallet signer in any flow that uses `SignatureChecker` (e.g., `SharedVaultAutomator._validateAgentAllowance`).

---

## SharedVaultGateway

The Gateway is the **primary user entry point**. It wraps swap-aggregator calldata around the vault's strict proportional-deposit/withdraw interface so end users can deposit a single token (or native ETH) and receive shares without manually building the four-token mix.

### Deposit flow (`swapAndDeposit`)

```
1. Wrap msg.value → WETH if any
2. Pull declared input tokens from caller via transferFrom
3. For each swap[i] (caller-supplied router calldata):
     - approve tokenIn for amountIn (or full balance if amountIn == 0)
     - call swapRouter with swapData
     - verify output delta ≥ amountOutMin
4. Read gateway balance for each vault token slot → enforce per-slot post-swap minimum
5. Approve vault for each non-zero amount
6. vault.deposit(amounts, slippageBps) → receive shares
7. Sweep all leftover balances back to caller (including unwrap WETH → ETH if msg.value was set)
```

### Withdraw flow (`withdrawAndSwap`)

```
1. Pull shares from caller via transferFrom
2. vault.withdraw(shares, minWithdrawAmounts, false)  // gateway holds all withdrawn tokens
3. For each swap[i]: convert vault tokens → desired output via swapRouter
4. Sweep all balances to caller (unwrap WETH if `unwrapOnWithdraw`)
```

### Trust assumptions

- `swapRouter` is settable by the gateway owner; caller-supplied `swapData` is fully trusted to call any function the router exposes (within the gateway's approval-limited token scope). The router must NOT expose admin functions consumable by user calldata.
- `swap.amountOutMin` and per-slot `minDepositAmounts` are the user's slippage controls.
- There is currently NO end-to-end `minShares` parameter (see audit W-18); users with multi-step swap routes should monitor that swap slippage protects them.

---

## SharedVaultFactory

`OwnableUpgradeable + PausableUpgradeable + Withdrawable`. Deploys vaults via `Clones.cloneDeterministic` with salt `keccak256(abi.encodePacked(name, msg.sender, "shared-1.0"))` (note: `abi.encodePacked` salt — caller-name pair collisions are theoretically possible; tracked as audit W-8).

Two overloads:
- `createVault(name, tokens, initialAmounts, vaultOwnerFeeBasisPoint)` — caller becomes owner immediately; operator = factory.owner().
- `createVault(name, tokens, initialAmounts, vaultOwnerFeeBasisPoint, actions[])` — factory becomes temporary owner; runs `execute(actions)` once (factory is permanently `onlyAuthorized` for this); transfers ownership + INITIAL_SHARES to caller.

ETH path: full `msg.value` is wrapped to WETH (factory expects `initialAmounts[wethIndex] == msg.value` exactly).

---

## SharedVaultAutomator

`CustomEIP712("V3AutomationOrder", "5.0") + AccessControl + Pausable + Withdrawable`.

Two flows, both gated by `OPERATOR_ROLE`:
- `executeWithAgentAllowance(vault, actions[], abiEncodedAllowance, signature)` — long-lived; expires via `expirationTime`; vault binding enforced via `require(allowance.vault == vault)`.
- `executeWithUserOrder(vault, actions[], abiEncodedOrder, sig)` — **currently reusable** (audit C-1: plan said one-time; implementation is reusable until cancelled or expired).

`cancelOrder(hash, sig)` keys cancellation on the digest globally. **Caveat (audit C-3):** anyone who knows the digest can sign + cancel it on behalf of the original signer. Recommended fix: key on `(canceller, hash)`.

EIP-1271 support: `SignatureChecker.isValidSignatureNow(owner, digest, sig)` works for both EOA and smart-wallet vault owners.

---

## Strategies (Beacon + Proxy pattern)

Each strategy type (V3, V4, Aerodrome, optionally Pancake V3) gets:
1. A logic contract (`SharedV3Strategy`, etc.) — deployed once, never changed in place.
2. A `SharedStrategyBeacon` — stores the current implementation address; protocol-multisig-owned.
3. A `SharedStrategyProxy` — forwards every call via delegatecall to `beacon.implementation()`. The beacon address is `immutable` (in bytecode), so the proxy holds zero storage of its own → safe when called via vault's delegatecall (no storage collision with vault's layout).

**Upgrade:** call `beacon.setImplementation(newImpl)`. All vaults using that beacon's proxy switch to the new logic immediately (no per-vault migration). **Caveat (audit W-3):** no timelock; recommend wrapping the beacon owner in a Timelock multisig.

**Whitelist:** only the proxy address goes into `configManager.whitelistedTargets` — the impl behind the beacon never needs re-whitelisting on upgrade.

### Strategy interface (`ISharedStrategy`)

```solidity
function execute(bytes data) external payable returns (PositionChange[] memory);
function exitProportional(nfpm, tokenId, shares, totalShares, minA0, minA1, vaultOwnerFeeBps)
    external returns (PositionChange[] memory);
function depositProportional(nfpm, tokenId, amount0, amount1, slippageBps) external;
function collectFees(nfpm, tokenId, vaultOwnerFeeBps) external;
function getPositionAmounts(nfpm, tokenId) external view returns (uint256, uint256);
function getPositionPrincipalAmounts(nfpm, tokenId) external view returns (uint256, uint256);
function getPositionTokens(nfpm, tokenId) external view returns (address, address);
```

### Per-strategy operation types

**SharedV3Strategy:** `SWAP_AND_MINT`, `SWAP_AND_INCREASE`, `SAFE_TRANSFER_NFT` (delegating to V3Utils for CHANGE_RANGE, WITHDRAW_AND_COLLECT_AND_SWAP, etc. via the NFT-receive callback). Tracked positions detected via `tokenOfOwnerByIndex` after CHANGE_RANGE.

**SharedV4Strategy:** `EXECUTE` (forwards to V4UtilsRouter), `SAFE_TRANSFER_NFT`. Uses Permit2 for `depositProportional`. Detects new positions by snapshotting `pm.nextTokenId()` before and after each call. **Caveat (audit C-4):** the inner `Instructions.params` are not currently validated — operators submitting an `EXECUTE` action can include arbitrary inline swap calldata bypassing `isWhitelistedSwapRouter`.

**SharedAerodromeStrategy:** Same surface as V3 but uses Aerodrome's tickSpacing-based pool lookup (`ICLFactory.getPool(t0, t1, tickSpacing)`). No gauge / farming support in this strategy — Aerodrome positions cannot be staked from a shared vault (audit W-12).

**PancakeSwap V3 / SushiSwap V3:** ABI-compatible with Uniswap V3; reuse `SharedV3Strategy` and just whitelist the protocol's NFPM separately. No dedicated strategy contract.

---

## Fee Model

Fees apply only to **LP-related token flows**, not to vault shares or principal.

| Fee | Source | Applied to | Recipient |
|---|---|---|---|
| `platformFeeBasisPoint` | `ConfigManager` (mutable) | LP performance collections | `feeRecipient` |
| `vaultOwnerFeeBasisPoint` | Vault (locked at init) | LP performance collections | `vaultOwner` |
| `gasFeeX64` | V3Utils / V4UtilsRouter calldata | Principal on rebalance/decrease | `gasFeeRecipient` |

`SharedStrategyFeeConfig.performanceFeeConfig` builds the FeeConfig used by `LpFeeTaker.takeFees` for V3/Aerodrome flows. If `platformBps + ownerBps > 10000`, the owner share is silently clamped (`ownerBps := 10000 − platformBps`). The protocol can raise `platformFeeBasisPoint` to squeeze the vault-owner share — depositors should treat the vault-owner share as a ceiling, not a guarantee.

V4 implements the fee split inline (`SharedV4Strategy._applyFees`) because V4 uses Permit2 + flash-accounting and is incompatible with the `LpFeeTaker.takeFees(token0, total0, token1, total1, fc, …)` approve-then-pull pattern.

**`collectFees` runs BEFORE the idle snapshot in `withdraw`**, so accrued LP fees are distributed proportionally across all shareholders, not handed entirely to the current withdrawer.

---

## Constants & Defaults

| Constant | Value | Where |
|---|---|---|
| `INITIAL_SHARES` | 10e18 | `SharedVault` (always minted on first deposit) |
| `SHARES_PRECISION` | 1e18 | `SharedVault` |
| `maxPositions` default | 20 | `SharedConfigManager.initialize` |
| `minTokenPrecision` default | 5 (→ 0.00001 of any token) | `SharedConfigManager.initialize` |
| `MAGIC_VALUE` (EIP-1271) | 0x1626ba7e | `SharedVault` |

---

## Verification

```
forge build                                    # all contracts compile
forge test --match-contract SharedVaultTest    # 131 unit tests
forge test --match-contract SharedVaultGatewayTest          # 53 tests
forge test --match-contract SharedVaultAutomatorTest        # 32 tests
forge test --match-contract SharedVaultFactoryTest          # 34 tests
forge test --match-contract SharedConfigManagerTest         # 49 tests
forge test --match-contract SharedStrategyProxyTest         # 17 tests
forge test --match-contract SharedStrategyBeaconTest        # 10 tests
forge test --match-contract SharedStrategyApprovalsTest     # 3 tests
forge test --match-contract SharedStrategyGuardsTest        # 3 tests
forge test --match-contract SharedVaultAuditTest            # 16 audit-regression tests
forge test --match-contract SharedVaultFuzzTest             # 5 fuzz suites × 256 runs
```

Integration tests under `test/integration/Integration.SharedVault*.t.sol` cover real-fork V3, Aerodrome, PancakeV3, SushiV3, Gateway, Automator, Swap, and MultiProtocol flows.

---

## Reuse Summary

| Component | Source | Use |
|---|---|---|
| `FullMath` | `@uniswap/v3-core` | Share math (`mulDiv`, `mulDivRoundingUp`) |
| `SafeERC20`, `IERC20Metadata` | OpenZeppelin | Token transfers + decimals probe |
| `SafeApprovalLib` | `private-vault/libraries/` | USDT-safe `safeResetAndApprove` |
| `ERC20PermitUpgradeable` | OpenZeppelin | Share token with EIP-2612 |
| `Clones` | OpenZeppelin | Deterministic factory deploys |
| `Withdrawable` | `contracts/common/` | Factory + automator + gateway sweep |
| `SignatureChecker` | OpenZeppelin | EIP-1271 in automator + vault |
| `AgentAllowanceStructHash` | `common/libraries/strategies/` | EIP-712 for AgentAllowance |
| `LpUniV3StructHash` | `common/libraries/strategies/` | EIP-712 for UserOrder (LpV3 type) |
| `CustomEIP712` | `private-vault/core/` | EIP-712 domain separator |
| `IV3Utils` | `private-vault/interfaces/strategies/lpv3/` | V3 family LP operations |
| `IV4UtilsRouter` | `private-vault/interfaces/strategies/lpv4/` | V4 LP operations |
| `LpFeeTaker` | `public-vault/interfaces/strategies/` | Platform + vault-owner fee dispatch (V3/Aerodrome) |
| `INonfungiblePositionManager` (Aero) | `common/interfaces/protocols/aerodrome/` | Aerodrome NFPM with tickSpacing |
| `IPositionManager` (V4) | `@uniswap/v4-periphery` | V4 PositionManager |
| `IPermit2`, `IAllowanceTransfer` | `permit2/src/interfaces/` | V4 Permit2 flow |
| `StateLibrary`, `TickMath` (V4) | `@uniswap/v4-core` | V4 pool state reads + tick → sqrtPrice |
| `LiquidityAmounts` | `@uniswap/v3-periphery` | sqrtPrice + liquidity → amounts |
