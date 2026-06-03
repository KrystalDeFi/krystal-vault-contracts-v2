# SharedVault — Trust Model & Assumptions

> **Related docs:** [README.md](README.md) · [Audit.md](Audit.md)

## Overview

SharedVault uses a layered permission system. Each layer carries a different blast radius if compromised. This document maps every trust boundary, what it can do, and what the worst-case impact is.

---

## Trust Layers (highest to lowest blast radius)

### 1. ConfigManager Owner (Protocol Multisig) — CRITICAL

**Controls:** `SharedConfigManager.setWhitelistTargets()`

This is the most dangerous key in the system. Because `SharedVault.execute()` delegatecalls into any address on the `whitelistedTargets` list, adding a malicious contract to that whitelist allows it to run arbitrary code **in the vault's storage context**. A malicious delegatecall can:

- Overwrite any storage slot (drain token balances, change `vaultOwner`, disable pauses)
- Call `safeTransfer` on any ERC20 in the vault's name

**Attack path:**
```
ConfigManager.setWhitelistTargets([maliciousContract], true)
  → any authorized execute() caller triggers vault.execute([{DELEGATECALL, maliciousContract, ...}])
  → maliciousContract.delegatecall runs in vault storage context
  → full vault drain
```

**There is no timelock** on `setWhitelistTargets`. A compromised multisig key can whitelist and exploit in a single block.

**Scope:** All vaults sharing this `ConfigManager` instance are affected simultaneously.

**Other ConfigManager powers:**

| Setting | Impact if abused |
|---------|-----------------|
| `setWhitelistCallers` | Grant `execute()` to an attacker address |
| `setWhitelistNfpms` | Allow tracking positions in malicious NFT contracts |
| `setWhitelistSwapRouters` | Allow vault funds to be swapped to attacker-controlled output |
| `setPlatformFeeBasisPoint` | Raise platform fee to near 100% (capped at 10,000 bps combined) |
| `setVaultPaused(true)` | Freeze all deposits/withdrawals globally |
| `setMaxPositions(n)` below current count | Blocks creation of *new* LP positions (existing positions still exit; `0` reverts) |

---

### 2. SharedStrategyBeacon Owner (Protocol Multisig) — CRITICAL

**Controls:** `SharedStrategyBeacon.setImplementation()`

All strategy proxies read their implementation address from the beacon. Swapping the implementation to a malicious contract causes every subsequent `delegatecall` from **every vault** (deposit top-ups, fee collection, withdrawals) to execute malicious code in vault context.

**Attack path:**
```
beacon.setImplementation(maliciousStrategy)
  → vault.withdraw() → pos.strategy.delegatecall(collectFees) → malicious code in vault context
  → triggered automatically on next user withdraw — no extra execute() call needed
```

**Scope:** Every vault that holds a position tracked against this beacon's strategy proxy.

**No timelock** on `setImplementation`.

---

### 3. vaultOwner — HIGH (per-vault)

**Controls:** `execute()`, admin management, `dropPosition`, `transferOwnership`, `setPaused`

`execute()` with `DELEGATECALL` is already restricted to whitelisted targets — so the vaultOwner cannot delegatecall arbitrary contracts on their own. However, a vaultOwner can:

- Call `execute()` with a whitelisted swap router (`CALL` type) to swap vault tokens at an unfavorable rate, effectively extracting value from depositors
- Grant admin role to an attacker address
- Drop LP positions, disrupting depositor value (the NFT is sent to the operator when one is set; with no operator it is stranded in the vault — see [Audit.md M-04](Audit.md))
- Pause the vault, blocking withdrawals
- Transfer ownership to an attacker

**Scope:** Single vault only.

**Note:** `vaultOwnerFeeBasisPoint` is **locked at initialization** — the vaultOwner cannot retroactively hike the performance fee. (The *configured* value is fixed, but the *effective* fee can be clamped downward if the protocol raises the platform fee — see [Audit.md M-01](Audit.md).)

#### Swap Execution — Accepted Trust Assumption

The `execute(CALL)` swap path has intentionally minimal on-chain validation:

```
execute([{callType: CALL, target: swapRouter, data: abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata)}])
```

**What the contract validates:**
- `swapRouter` must be on `configManager.whitelistedSwapRouters`
- `tokenIn` and `tokenOut` must both be configured vault tokens
- `amountOut >= minAmountOut` (measured via vault balance delta after the swap)

**What the contract does NOT validate:**
- `minAmountOut` has no floor — it can be 1 wei, allowing a near-total loss of `tokenIn`
- The `recipient` field inside `swapCalldata` is opaque bytes — the contract cannot enforce that output is routed back to the vault
- No cap on `amountIn` — the entire vault balance of a token can be swapped in one call
- No cooldown between swaps — swaps can be executed back-to-back

**Why this is intentional:**

SharedVault is designed as a **managed fund**. The vault owner may pursue aggressive, high-frequency strategies — large position entries, rapid rotations between tokens, or opportunistic apes into new assets. Imposing size caps, cooldowns, or price oracle checks would make these strategies impossible.

Since vault tokens are an arbitrary set chosen by the vault owner, no general-purpose on-chain price oracle can cover all possible pairs. The contract therefore cannot validate swap fairness without introducing rigid constraints that contradict the fund management use case.

**The trade-off:**

> Depositors give the vault owner full discretion over swap execution in exchange for the ability to participate in an actively managed, high-flexibility LP strategy. This is the same trust relationship as any managed fund: the depositor is trusting the vault owner to act in their interest.

**What depositors must accept:**
- The vault owner (and any admin they grant) can swap vault tokens at any rate, in any size, at any time
- A compromised or malicious vault owner can drain vault tokens through the swap path without the contract reverting
- The only on-chain protection is the router whitelist — output must come from a protocol-approved aggregator

**Recommended operational controls (off-chain):**
- Vault owners using the automator should commit to `minAmountOut` at signing time using a live DEX quote, not leave it to the bot to fill
- The automator signing service should decode `swapCalldata` and verify the `recipient` matches the vault address for known aggregator formats
- Depositors should verify the vault owner's identity and track record before depositing into a vault with active swap operations

#### Strategy Fee Parameters — Accepted Trust Assumption

The `execute(DELEGATECALL)` path allows callers to pass `gasFeeX64` as part of strategy `action.data`. This parameter controls a gas reimbursement fee paid to `msg.sender` (the execute() caller) via `SharedStrategyFees.applyFees()`.

**What the contract does NOT validate:**
- `gasFeeX64` has no hard cap — it is a `uint64` and can be set to any value up to `2^64 - 1`
- On decrease and range-change operations (`_decreasePrincipal`), the fee is applied to the **full principal amount** returned from liquidity removal, not just accumulated LP fees
- There is no minimum threshold or oracle check on what constitutes a "reasonable" gas reimbursement

**Concrete mechanism:**
```
execute([{DELEGATECALL, strategy, Instructions{
  whatToDo: WITHDRAW_AND_COLLECT_AND_SWAP,
  gasFeeX64: X    // caller-supplied, no cap
}}])
→ _decreasePrincipal() removes LP liquidity, receives principal tokens
→ SharedStrategyFees.applyFees(): fee = principal × (X / 2^64) → sent to msg.sender
→ vault retains principal × (1 - X / 2^64)
```

**Why this is intentional:**

`gasFeeX64` exists to reimburse operators for gas costs on automated strategy operations (rebalancing, compounding, range changes). In a managed fund model, the vault owner and authorized callers are trusted to set this parameter at values that reflect actual gas costs — not as an extraction mechanism.

The same trust principle that governs swap execution applies here: depositors are participating in an actively managed vault and trust the vault owner to act in their interest. Just as the vault owner could extract value through swaps with unfavorable rates, they could also extract value through excessive gas fees. These are two facets of the same trust surface.

**What depositors must accept:**
- The vault owner (and any admin or automator they authorize) can set `gasFeeX64` to any value in strategy operations
- A malicious or compromised authorized caller can set `gasFeeX64` near `2^64` to route most of the LP principal to themselves on any decrease operation
- There is no on-chain protection against excessive `gasFeeX64` values

**Recommended operational controls (off-chain):**
- The automator signing service should validate that `gasFeeX64` in signed orders does not exceed a reasonable threshold (e.g., ≤ 1% of expected principal)
- Vault owners should emit and monitor events to confirm gas fees match expected reimbursement amounts
- Depositors should treat vaults using automated strategy operations the same as any managed fund: vet the vault owner before depositing

---

### 4. operator — MEDIUM (per-vault)

**Controls:** `sweepTokens`, `sweepNativeToken`, `sweepERC721`, `sweepERC1155`, `recoverPosition`, `dropPosition`

The operator can sweep non-vault tokens that land in the vault (e.g., airdropped tokens, accidentally sent ERC20s). It cannot sweep the vault's own configured tokens (`CannotSweepVaultToken` guard) or tracked LP position NFTs (`sweepERC721` blocks tracked tokenIds).

`recoverPosition` is guarded: requires NFPM whitelist, token pair validation, and `isWhitelistedTarget` for the strategy.

**Scope:** Single vault only. Cannot extract depositor principal directly.

---

### 5. admin — LOW (per-vault)

**Controls:** `execute()` only (same as vaultOwner for LP ops and swaps)

Admins share the `execute()` surface with `vaultOwner`. They can perform all LP operations and swaps but cannot manage roles, pause the vault, or drop positions.

---

### 6. whitelistedCaller (Automator) — LOW (per-vault)

**Controls:** `execute()` only, via EIP-712 signed orders checked by `SharedVaultAutomator`

Same `execute()` surface as admins. The automator adds an additional EIP-712 signing layer — vault owner signs an `AgentAllowance` or `UserOrder` before the operator can act.

---

## Delegatecall Attack Surface Summary

All `delegatecall` paths in `SharedVault` flow through one of these entry points:

| Entry point | Target validation | Who can trigger |
|---|---|---|
| `execute(DELEGATECALL)` | `configManager.isWhitelistedTarget` | owner, admin, whitelisted caller |
| `deposit → depositProportional` | target was whitelisted when position was created | anyone (depositor) |
| `withdraw → collectFees` | target was whitelisted when position was created | anyone (withdrawer) |
| `withdraw → exitProportional` | target was whitelisted when position was created | anyone (withdrawer) |
| `recoverPosition` | `configManager.isWhitelistedTarget` (checked inline) | operator only |

**The security invariant:** a delegatecall target can only reach the vault's storage if it is (or was, when the position was created) on `configManager.whitelistedTargets`. The ConfigManager owner is therefore the root of trust for the entire delegatecall surface.

---

## What Users Must Trust

When depositing into a SharedVault, a user implicitly trusts:

1. **The protocol multisig** will not add a malicious address to `whitelistedTargets` or `setImplementation` on any beacon used by the vault.
2. **The vaultOwner** has full discretion over swap execution — size, rate, frequency, and routing are entirely at the vault owner's discretion. Depositors accept that the vault owner may swap any amount of vault tokens at any rate as part of their fund management strategy, and that a malicious or compromised vault owner could use this to extract value.
3. **The ConfigManager owner** will not use `setWhitelistSwapRouters` to allow value extraction via swap calls.
4. **The operator** (if set) will not collude with anyone to abuse `sweepTokens` on non-vault tokens or `recoverPosition` with a malicious strategy address (though this is guarded by whitelisting).

---

## Mitigations & Recommendations

| Risk | Current state | Recommended mitigation |
|------|--------------|------------------------|
| ConfigManager owner can whitelist arbitrary delegatecall target | No timelock | Add a timelock (e.g., 48h) on `setWhitelistTargets` |
| Beacon owner can hot-swap strategy impl instantly | No timelock | Add a timelock on `setImplementation` |
| vaultOwner swap discretion (rate, size, recipient) | Intentional — managed fund design | Off-chain: automator commits minAmountOut from live quote at signing time; signing service validates recipient in swapCalldata |
| vaultOwner strategy-fee discretion (`gasFeeX64` applied to principal, no cap) | Intentional — managed fund design | Off-chain: automator signing service caps `gasFeeX64` (e.g. ≤ 1%); monitor fee events |
| Global pause by ConfigManager owner | Instant, no delay | Acceptable for emergency; document expected use policy |
| No on-chain record of multisig threshold/signers | Offchain | Publish multisig address and threshold in deployment notes |
