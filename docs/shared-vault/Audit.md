# SharedVault — Internal Security Audit

> **Type:** Internal audit  
> **Date:** 2026-06-03  
> **Commit:** `ddda055957294c6819d7250669fc6de447b47b0a` (Merge branch 'main' into feat/shared-vault)  
> **Scope:** `contracts/shared-vault/` — all core, strategy, library, and interface contracts  
> **Related docs:** [README.md](README.md) · [TrustModel.md](TrustModel.md)

---

## Scope

| Area | Files |
|---|---|
| Core | SharedVault.sol, SharedConfigManager.sol, SharedVaultFactory.sol |
| Periphery | SharedVaultGateway.sol, SharedVaultAutomator.sol |
| Strategies | SharedV3Strategy.sol, SharedV4Strategy.sol, SharedAerodromeStrategy.sol, SharedPancakeV4Strategy.sol |
| Infrastructure | SharedStrategyBeacon.sol, SharedStrategyProxy.sol |
| Libraries | SharedStrategyFees.sol, SharedStrategyFeeConfig.sol, SharedVaultPreviewLib.sol, SharedNfpmProportionalExit.sol, SharedStrategyGuards.sol |

---

## Methodology

1. Read all contracts in full
2. Map every function that moves tokens or delegatecalls external code
3. Trace all privileged actor capabilities (owner, admin, operator, protocol multisig)
4. Verify share accounting invariants (first deposit, subsequent deposits, withdrawals)
5. Validate every finding against the exact source
6. Cross-reference with [TrustModel.md](TrustModel.md) — documented accepted trade-offs are not classified as bugs

---

## Summary

| ID | Title | Severity |
|----|-------|----------|
| C-01 | No timelock on ConfigManager whitelist additions | Critical |
| H-01 | Removed-whitelist strategy still delegatecalled on existing positions | High |
| M-04 | `dropPosition` strands LP NFT when `operator` is unset | Medium |
| H-03 | Single-step vault ownership transfer | Medium |
| M-01 | Vault owner effective fee silently reduced, no event | Medium |
| M-03 | `tokenIn == tokenOut` not validated in execute CALL swap | Medium |
| M-05 | Platform fee has no hard cap below 100% | Medium |
| L-01 | `maxPositions` has no upper cap — gas DoS risk | Low |
| M-02 | `exitProportional` returns empty on dust-sized withdrawal | Info |
| M-06 | `minTokenPrecision = 0` disables dust floor | Info |
| L-02 | Strategy approval list skips validation on zero-amount entries | Info |
| L-03 | `previewWithdraw` may diverge by 1–2 wei | Resolved |
| H-02 | AgentAllowance has no per-execution nonce | Accepted risk → Trust Model |
| — | Gateway accepts arbitrary vault address | Rejected (false positive) |

---

## Confirmed Findings

---

### C-01 — No timelock on ConfigManager whitelist additions

**Severity:** Critical  
**File:** `SharedConfigManager.sol:88-97,103-112` — `setWhitelistTargets()`, `setWhitelistCallers()`

**Description:**

Both setters execute immediately with no timelock, delay, or two-step acceptance:
```solidity
function setWhitelistTargets(address[] calldata targets, bool _isWhitelisted) external override onlyOwner {
    for (uint256 i; i < targets.length;) {
        whitelistedTargets[targets[i]] = _isWhitelisted;
        unchecked { i++; }
    }
    emit WhitelistTargetsUpdated(targets, _isWhitelisted);
}
```

Because `SharedVault.execute()` delegatecalls any address on `whitelistedTargets`, a compromised ConfigManager owner key can whitelist a malicious contract and drain all vaults in a single block. Also noted in [TrustModel.md §1](TrustModel.md) as a protocol-level risk; listed here because it is fixable in code.

A timelock protects against a single compromised signer key, not against a compromised multisig quorum — so effective severity is Critical for single-key ownership and High for a well-distributed multisig.

**Recommended fix:** Apply a ≥ 48h timelock to whitelist **additions** only. Removals (`isWhitelisted=false`) should remain instant so the protocol can react to compromises quickly.

---

### H-01 — Removed-whitelist strategy still delegatecalled on existing positions

**Severity:** High  
**Files:** `SharedVault.sol` — `_depositProportionalToAllPositions()` (lines 492-495), `_withdraw()` collectFees (566-571) and exitProportional (591-597) loops

**Description:**

When a position is created, `pos.strategy` is validated as whitelisted (via `_applyPositionChanges` → `_addPosition`). On subsequent deposit top-ups, fee collection, and proportional exits, the vault delegatecalls `pos.strategy` **without re-checking** `configManager.isWhitelistedTarget(pos.strategy)`:
```solidity
(bool ok, bytes memory result) = pos.strategy.delegatecall(
    abi.encodeCall(ISharedStrategy.exitProportional, (...))
);
```

If a strategy is removed from the whitelist after a vulnerability is found, existing positions still delegatecall it — defeating the purpose of removal.

The "full drain" scenario requires the strategy contract to actually *become* malicious. Strategies sit behind a beacon (`SharedStrategyProxy` → `SharedStrategyBeacon`), so this only materializes via a beacon implementation swap — which is itself a documented protocol-multisig trust risk ([TrustModel.md §2](TrustModel.md)). An immutable, already-deployed strategy does not become exploitable merely by being de-whitelisted, and `dropPosition` provides a partial manual mitigation — hence High rather than Critical. It remains a real defense-in-depth gap.

**Recommended fix:** Add `require(configManager.isWhitelistedTarget(pos.strategy))` before each delegatecall on `pos.strategy`, paired with a `migratePosition(nfpm, tokenId, newStrategy)` function so positions on a de-whitelisted strategy can be moved rather than bricked (a hard revert alone would block withdrawals).

---

### M-04 — `dropPosition` strands LP NFT when `operator` is unset

**Severity:** Medium  
**File:** `SharedVault.sol:901-908` — `dropPosition()`, `sweepERC721()` (859-863)

**Description:**

This is the most concrete code bug in the set. `dropPosition` is callable by `vaultOwner` or `operator`, but only transfers the NFT out if an operator is set:
```solidity
function dropPosition(address nfpm, uint256 tokenId) external override {
    require(_msgSender() == vaultOwner || (operator != address(0) && _msgSender() == operator), Unauthorized());
    require(positionIndex[key] != 0, InvalidOperation());
    _removePosition(nfpm, tokenId);
    if (operator != address(0)) IERC721(nfpm).safeTransferFrom(address(this), operator, tokenId);
    emit PositionDropped(vaultFactory, nfpm, tokenId);
}
```

When `operator == address(0)`, `vaultOwner` can still call it: the position is untracked but the NFT stays in the vault. Recovery is then impossible because `sweepERC721` is `onlyOperator`:
```solidity
function sweepERC721(address token, uint256 tokenId, address to) external override onlyOperator {
    require(positionIndex[key] == 0, CannotSweepVaultToken());
    IERC721(token).safeTransferFrom(address(this), to, tokenId);
}
```

With no operator, the untracked NFT is permanently stranded.

**Recommended fix:** Transfer to `vaultOwner` as a fallback when no operator is set:
```solidity
address recipient = operator != address(0) ? operator : vaultOwner;
IERC721(nfpm).safeTransferFrom(address(this), recipient, tokenId);
```

---

### H-03 — Single-step vault ownership transfer

**Severity:** Medium  
**File:** `SharedVault.sol:889-893` — `transferOwnership()`

**Description:**
```solidity
function transferOwnership(address newOwner) external override onlyOwner {
    require(newOwner != address(0), ZeroAddress());
    emit VaultOwnerChanged(vaultFactory, vaultOwner, newOwner);
    vaultOwner = newOwner;
}
```

Ownership transfers atomically with no acceptance step. A typo or wrong address permanently loses control of the vault. This matches the OpenZeppelin `Ownable` default and is mitigated by using a multisig/MPC wallet that reviews the target.

**Recommended fix:** Two-step pattern — `initiateOwnershipTransfer(newOwner)` + `acceptOwnership()` callable only by `pendingVaultOwner`.

---

### M-01 — Vault owner effective fee silently reduced, no event

**Severity:** Medium  
**File:** `SharedStrategyFeeConfig.sol:14-34` — `performanceFeeConfig()`

**Description:**

The effective owner fee is clamped at runtime so combined fees never exceed 100%:
```solidity
uint16 maxOwnerBps = 10_000 - platformBps;
fc.vaultOwnerFeeBasisPoint = vaultOwnerFeeBasisPoint > maxOwnerBps ? maxOwnerBps : vaultOwnerFeeBasisPoint;
```

If the protocol raises `platformFeeBasisPoint` after vault creation, the vault owner's collected share silently decreases. Example: created at platform=20% / owner=50%; protocol raises platform to 70%; owner now receives 30% with no notification.

The clamp itself is intentional and documented in the source (it prevents a broken fee config from bricking exits). The real gap is the **absence of an event** signaling the reduction — "locked at init" refers to the configured value, not the effective value.

**Recommended fix:** Emit `VaultOwnerFeeAdjusted(original, effective)` when clamping occurs, and document that the configured fee is a ceiling the platform-fee level can push down.

---

### M-03 — `tokenIn == tokenOut` not validated in execute CALL swap

**Severity:** Medium  
**File:** `SharedVault.sol:698-716` — `execute()` CALL branch

**Description:**

The swap branch validates both tokens are vault tokens and the router is whitelisted, but never checks `tokenIn != tokenOut`. The gateway has this guard (`SharedVaultGateway.sol:374` → `IdenticalSwapTokens`); the vault's own CALL path does not. A self-swap wastes gas and opens an unnecessary approval window; it is harmless when `minAmountOut > 0` (the balance-delta check reverts).

**Recommended fix:**
```solidity
require(tokenIn != tokenOut, InvalidToken());
```

---

### M-05 — Platform fee has no hard cap below 100%

**Severity:** Medium  
**File:** `SharedConfigManager.sol:161-165` — `setPlatformFeeBasisPoint()`

**Description:**
```solidity
function setPlatformFeeBasisPoint(uint16 basisPoints) external override onlyOwner {
    require(basisPoints <= 10_000, ISharedCommon.InvalidFeeBasisPoint());
    platformFeeBasisPoint = basisPoints;
}
```

The protocol owner can set platform fee to 100%. Important context: the platform fee is applied **only to LP performance fees (yield)**, never to principal (`SharedStrategyFees.sol:57-68`; principal is untouched). A 100% setting captures all yield, not deposits. Combined platform+owner is clamped to ≤ 100% at runtime (`SharedVault._performanceFeeBps`).

**Recommended fix:**
```solidity
uint16 public constant MAX_PLATFORM_FEE_BPS = 1_000; // 10%
require(basisPoints <= MAX_PLATFORM_FEE_BPS, InvalidFeeBasisPoint());
```
Publish the cap as a documented protocol guarantee.

---

### L-01 — `maxPositions` has no upper cap

**Severity:** Low  
**File:** `SharedConfigManager.sol:167-171` — `setMaxPositions()`

**Description:**

`setMaxPositions` enforces `> 0` but no upper bound (up to `type(uint16).max`). The deposit/withdraw loops iterate all positions; a vault deliberately configured with hundreds of positions could exceed block gas limits and brick those operations. This requires owner cooperation to both raise the cap and add the positions (positions are only added by authorized callers); the realistic brick threshold is ~100–200 positions. Default is 20.

**Recommended fix:**
```solidity
require(_maxPositions > 0 && _maxPositions <= 100, InvalidAmount());
```

---

## Informational

Intentional documented behavior or standard accounting — not bugs.

### M-02 — `exitProportional` returns empty on dust-sized withdrawal

**File:** `SharedV3Strategy.sol:338-373` — `exitProportional()`

When `liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares))` rounds to 0, the function returns an empty `PositionChange[]`. The withdrawer still receives their proportional idle balances via the vault's withdraw path; only the sub-wei LP slice rounds down, favoring remaining holders — standard, acceptable rounding. Position tracking stays intact.

A hard revert on `liquidityToRemove == 0` would brick all dust-sized withdrawals, which is worse than the rounding — so no code change is recommended beyond optionally documenting the behavior.

### M-06 — `minTokenPrecision = 0` disables dust floor

**File:** `SharedConfigManager.sol:173-176`

Setting `0` to disable the floor is an explicitly documented feature. `ISharedConfigManager` NatSpec: *"A value of 0 disables the floor (ceiling rounding still prevents the dilution attack)."* The dilution attack remains mitigated by ceiling rounding even at 0. Optionally add `require(precision > 0)` if the team wants to forbid accidental disabling.

### L-02 — Strategy approval list skips validation on zero-amount entries

**File:** `SharedV3Strategy.sol:991-1006` — `_validateApprovalList()`

Per the source comments, this list is **metadata only** and is *not* used to issue ERC20 approvals (those happen per-hop inside `_swap` against the immutable `swapRouter`). A zero-amount entry to a non-vault token is a no-op with no exploitable effect. Intentional design.

---

## Resolved

### L-03 — `previewWithdraw` divergence

**File:** `SharedVaultPreviewLib.sol:168-185`, `SharedV3Strategy.sol:937-950`

The code already addresses this. `netAfterPerformanceFees()` mirrors `SharedStrategyFees.applyFees()` to the wei (sequential floor division from the original amount, not a combined-bps division), and `getPositionAmounts` accumulates fee growth in uint256 to avoid the uint128 wrap. Source comments document that the prior 1-wei under-report was the reason for this design. No open issue.

---

## Findings Deferred to Trust Model (Accepted Risks)

Intentional design decisions documented in [TrustModel.md](TrustModel.md); not classified as bugs.

| Topic | TrustModel reference |
|---|---|
| **H-02** — AgentAllowance has no nonce; valid signature is replayable until expiry | §6 — whitelistedCaller. By design: a long-lived delegation (like an approval), bounded by `expirationTime`, revocable via `cancelOrder`. Source recommends `executeWithUserOrder` for one-time scoped actions. |
| `execute(CALL)` swap — `minAmountOut` uncapped; caller can set 1 wei | §3 — Swap Execution: Accepted Trust Assumption |
| `execute(CALL)` swap — `swapCalldata` recipient not validated | §3 — Swap Execution: Accepted Trust Assumption |
| `execute(DELEGATECALL)` — caller-supplied `gasFeeX64` applied to LP principal; routed to `msg.sender` with no cap | §3 — Strategy Fee Parameters: Accepted Trust Assumption |
| Beacon `setImplementation` — instant, no timelock | §2 — SharedStrategyBeacon Owner |
| ConfigManager whitelist changes — protocol multisig trust | §1 — ConfigManager Owner |

**Operational recommendation for H-02:** The automator signing service should enforce short expiration windows (e.g., ≤ 1 hour) on `AgentAllowance` signatures, since the on-chain contract intentionally permits replay within the window.

---

## Rejected (False Positives)

### Gateway accepts arbitrary vault address

**File:** `SharedVaultGateway.sol` — `swapAndDeposit()`, `withdrawAndSwap()`

`params.vault` is caller-supplied with no factory validation, but this is not exploitable. The gateway is **stateless within a transaction**: it pulls the caller's *own* tokens, approves the vault, deposits, revokes approvals, and sweeps leftovers back to the caller — all atomically. It holds no funds or lingering approvals between calls. If a user passes a fake vault, they can only rob *themselves*; an attacker cannot force a third party to supply a fake vault address. There is no cross-user exploit. (Callers should still source vault addresses from a trusted registry, but that is a client-side concern.)

---

## Recommendations by Priority

### Immediate (before mainnet)

| Priority | Finding | Effort |
|---|---|---|
| 1 | **C-01** — Timelock on whitelist additions in ConfigManager | Medium |
| 2 | **H-01** — Re-validate `pos.strategy` before delegatecall; add `migratePosition()` | Medium |
| 3 | **M-04** — Fallback NFT recipient (`vaultOwner`) in `dropPosition` | Low |

### Before production launch

| Priority | Finding | Effort |
|---|---|---|
| 4 | **H-03** — Two-step ownership transfer | Low |
| 5 | **M-05** — Hard cap on platform fee | Low |
| 6 | **M-03** — `require(tokenIn != tokenOut)` in execute CALL | Trivial |
| 7 | **M-01** — Emit event when vault owner fee is clamped | Low |

### Hardening (post-launch)

| Priority | Finding | Effort |
|---|---|---|
| 8 | **L-01** — Upper cap on `maxPositions` | Trivial |

### Operational (off-chain policy)

| Priority | Finding | Action |
|---|---|---|
| 9 | **H-02** — Enforce short `AgentAllowance` expiry windows in the signing service | Policy |
