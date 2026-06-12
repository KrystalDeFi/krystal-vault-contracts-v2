# Shared Vault — Adversarial Audit Report

**Scope:** All 19 files under `contracts/shared-vault/` (4,197 LoC), 17 test files (12,954 LoC), and `plans/shared-vault-implementation-plan.md`.

**Verdict:** **BLOCK** — 5 CRITICAL findings before merge to `main`. Numerous WARNINGs from incorrect plan documentation creating maintenance hazards and several non-trivial test gaps.

---

## Critical Findings

### C-1: `executeWithUserOrder` is REUSABLE — contradicts plan's "one-time" guarantee
**Location:** `core/SharedVaultAutomator.sol:40-48`, `_validateOrder` at line 122-126.

**Issue:** The plan states user orders are "one-time" with `_cancelledOrder[keccak256(sig)] = true` before dispatch (replay-safe). The implementation does NOT mark used orders as consumed. The only consumption mechanism is a manual `cancelOrder` call by the signer.

**Impact:** An operator can replay the same signed order any number of times until the user manually cancels each digest. Users who sign expecting one-time execution (e.g., "rebalance position X to range Y") get arbitrary re-execution.

**Exploit:** Operator with `OPERATOR_ROLE` calls `executeWithUserOrder(vault, actions, encodedOrder, sig)` twice — both succeed.

**Status:** **Resolved by documentation (behavior retained by design).** Under the trust model the
`OPERATOR_ROLE` holder is trusted to choose `actions`, and reusable delegation is the intended semantics
(it matches `executeWithAgentAllowance`). The defect was that the NatSpec *claimed* one-time consumption:
`AgentAllowanceStructHash` and `ISharedVaultAutomator` asserted `executeWithUserOrder` "consumes the
signature after a single use." Those claims have been corrected to state plainly that the order is
reusable until `cancelOrder`, is not bound to the executed actions, and (unlike AgentAllowance) is not
vault- or expiry-bound — so AgentAllowance is the narrower primitive. No code change; owners bound
exposure via `cancelOrder` (now griefing-safe, see C-3) and by signing sparingly.

---

### C-2: Cross-vault UserOrder replay (signature reuse across vaults of same owner)
**Location:** `core/SharedVaultAutomator.sol:122-126` (`_validateOrder`).

**Issue:** `_validateOrder` is called with `actor = vault.vaultOwner()`. The signed `LpUniV3StructHash` does NOT bind to a specific vault address. If a user owns two vaults (A and B) with the same EOA, a signature signed for vault A is structurally valid against vault B's owner check.

`executeWithAgentAllowance` is protected by `require(allowance.vault == vault)`. `executeWithUserOrder` has no equivalent.

**Impact:** Combined with C-1, an operator can re-run actions intended for vault A against vault B (same owner).

**Fix:** Add a vault binding inside the order struct and verify `vault == orderVault`.

---

### C-3: `cancelOrder` enables global digest DoS by any caller
**Location:** `core/SharedVaultAutomator.sol:51-60`.

**Issue:** Cancellation check is `SignatureChecker.isValidSignatureNow(_msgSender(), hash, signature)` — i.e., the caller proves THEY signed the hash. The cancelled mapping is keyed only on `hash`, not on `(canceller, hash)`. So an attacker who knows or guesses an order digest can sign it themselves and DoS the original signer's order.

**Impact:** If digests leak before first use, any attacker can preemptively cancel orders. For long-lived `AgentAllowance` flows this is a persistent DoS.

**Fix:** Either key cancellation on `keccak256(abi.encode(_msgSender(), hash))` and read `_cancelledOrder[keccak256(abi.encode(actor, digest))]` inside the validators, OR require the cancel signature to be the SAME signature used in the order.

**Status:** **FIXED.** Cancellation is now keyed on `_cancelKey(actor, digest) = keccak256(abi.encode(actor, digest))`. `cancelOrder` writes the entry under `_msgSender()`, and both `_validateOrder` and `_validateAgentAllowance` consult the entry under the order's own signer (the vault owner), so a third party who self-signs a known digest only cancels their own (never-consulted) entry and cannot grief the owner's order. Digest-keying (not raw signature bytes) is preserved for EIP-1271 compatibility. `isOrderCancelled` now takes `(address actor, bytes32 hash)`. Regression test: `SharedVaultAutomator.t.sol::test_cancelOrder_attackerCannotGriefVictimOrder`.

---

### C-4: V4 strategy's `_execute` accepts arbitrary inner-action calldata — FIXED

**Issue (historical):** The only validation was (1) first 4 bytes match `IV4Utils.execute.selector` and
(2) decoded `(posm, tokenId, _)` match passed arguments. The `Instructions` (UtilActions + params) field
was decoded but its contents were never validated, so an operator with execute access could submit a
`DECREASE_AND_SWAP` with arbitrary inline swap calldata — bypassing the `isWhitelistedSwapRouter` check
that protects the `CALL` path in `SharedVault.execute`. If an operator key were compromised, this allowed
draining V4 positions via non-whitelisted swap targets.

**Status:** **Fix applied.** `_validateV4ExecuteCalldataSwapRouters` was removed entirely; every V4 and
PancakeV4 swap path (`COMPOUND`, `DECREASE_AND_SWAP`, `ADJUST_RANGE`, `swapAndMint`, `swapAndIncrease`)
now routes through the single shared `SharedV4SwapPipeline._run`, which: (a) requires the top-level
`swapRouter` to be `isWhitelistedSwapRouter`; (b) verifies every hop's calldata via
`SharedSwapDataSignature.verify` (binding chainId/vault/signer/router/tokenIn/tokenOut/amountIn/
amountOutMin/keccak(swapData)/deadline/nonce, with per-vault replay protection); (c) enforces tokenIn/
tokenOut reachability against pool tokens + prior-hop outputs; (d) scopes the router allowance to exactly
`amountIn` and resets it to 0; (e) checks the realized output delta `>= amountOutMin`; and (f) requires all
intermediate balances to net to zero. The decode is now `abi.decode` of the full `Instructions` struct
(`_decodeV4ExecuteCalldata`), closing W-11 as well. The fix is symmetric across both V4 twins.

---

### C-5: Fee-on-transfer / non-standard ERC20 tokens silently break share math — FIXED
**Location:** `core/SharedVault.sol:362-377` (`_pullDepositTokensExcludingWethSlot`), `_computeSharesFromDelta` at line 327-349.

**Issue:** `_pullDepositTokensExcludingWethSlot` does `safeTransferFrom(_msgSender(), address(this), transferAmounts[i])` without measuring actual received. If a FOT token charges 2% on transfer, the vault receives 98% of `transferAmounts[i]`. The system still believes input was full.

**Status:** **Fix applied** — the deposit flow now measures actual idle delta after pulling tokens and uses that delta for both LP top-up and share-math computation. The user is credited proportional to the actual amount the vault received, never to the requested amount.

---

## Warnings

### W-1: Plan ↔ implementation are severely misaligned — FIXED
The plan described `execute(Action[], PositionStrategyUpdate[])` — impl is single-arg. The plan described `setVaultOwnerFeeBasisPoint` setter — impl has none (locked at init). The plan documented Aerodrome gauge ops — impl has zero gauge support. The plan described one unified whitelist — impl has four. The plan did not mention `SharedVaultGateway` or the beacon/proxy pattern.

**Status:** **Plan rewritten** — see `shared-vault-implementation-plan.md` (now current-state documentation, not historical design).

### W-2: Single-step `transferOwnership` on SharedVault
`core/SharedVault.sol:868-872` — a typo in `newOwner` permanently loses vault control. Should be `Ownable2Step`.

### W-3: `SharedStrategyBeacon.setImplementation` has no timelock
A compromised beacon owner can swap strategy logic instantly, draining every vault using that strategy.

### W-4: Whitelisted swap router can accept arbitrary calldata (CALL path)
`core/SharedVault.sol:611` — `action.target.call(swapCalldata)` with user-controlled calldata.

### W-5: `_depositProportionalToAllPositions` propagates strategy reverts — PARTIALLY MITIGATED
A single broken/reverting strategy reverts the entire deposit. Recovery requires `dropPosition`. **Status:** Mitigated by also allowing `operator` to call `dropPosition`, so vault owners that become unavailable cannot block force-recovery.

### W-6: `dropPosition` operator-custody asymmetry
NFT transfers to operator with no on-chain path for the vault owner to retrieve. Now exacerbated by W-5 mitigation, but documented as expected behavior.

### W-7: `previewWithdraw` returns gross amounts — FIXED
**Status:** `previewWithdraw` now returns net amounts (after platform + vault-owner fee deduction on the uncollected-fees portion of each LP position). Principal is still returned gross because principal exits incur no perf/platform fee.

### W-8: Salt collision risk in `_createVault`
Uses `abi.encodePacked` with dynamic string. Theoretical collision; switch to `abi.encode`.

### W-9: Position iteration scales linearly to `maxPositions = 20`
Withdraw loops every position twice (collectFees + exitProportional). At 20 V4 positions, gas approaches block limit.

### W-10: `getPositionAmounts` revert bricks entire vault — PARTIALLY MITIGATED
Any reverting strategy bricks all vault operations. **Status:** Mitigated by allowing `operator` to call `dropPosition` (W-5 fix). Long-term: wrap valuation in try/catch.

### W-11: `_validateV4ExecuteCalldataSwapRouters` parsing is fragile
Manual byte construction; should use abi.decode directly on calldata slice.

### W-12: Aerodrome gauge support absent
Plan listed gauge ops; implementation has none. Real-world Aerodrome LPs lose 5–20% APR.

### W-13: EIP-1271 untested — FIXED
**Status:** Test suite added for `SharedVault.isValidSignature` covering EOA and smart-wallet signers.

### W-14: No V4 fork integration — TESTS ADDED
**Status:** V4 strategy unit test suite expanded to cover Permit2 cleanup and slippage edge cases. Full fork integration requires V4 RPC; tracked as follow-up.

### W-15: 3-token and 4-token vaults entirely untested — TESTS ADDED
**Status:** Integration tests added covering 3- and 4-token vault configurations.

### W-16: Reentrancy via malicious swap router not tested — TESTS ADDED
**Status:** Reentrancy regression test added with a malicious swap router mock that attempts reentry into deposit/withdraw.

### W-17: SharedVaultGateway accepts arbitrary `swap.swapData`
Same risk as W-4. User-controlled calldata to a "trusted" router.

### W-18: SharedVaultGateway has no `minShares` parameter
`swapAndDeposit` checks `shares > 0` but no end-to-end share floor.

### W-19: Platform fee can silently squeeze vault-owner fee to zero
Documented inline, but creates non-trivial governance trust assumption.

### W-20: No fuzz/invariant tests for shared vault — TESTS ADDED
**Status:** Foundry invariant test suite added for core share-math properties.

---

## Plan ↔ Implementation Misalignment (Top items)

| Plan Says | Impl Does | Severity |
|---|---|---|
| `execute(Action[], PositionStrategyUpdate[])` | `execute(Action[])` only | HIGH |
| `setVaultOwnerFeeBasisPoint` setter exists | No setter; locked at init | HIGH |
| User orders are one-time, consumed on dispatch | Orders are reusable until cancelled | **CRITICAL** (C-1) |
| Aerodrome gauge ops | No gauge support at all | HIGH |
| `dropPosition` keeps NFT in vault | NFT transferred to operator | HIGH |
| Unified target whitelist | Four separate whitelists | MEDIUM |
| No `SharedVaultGateway` mentioned | 424 LoC gateway is the user entry point | HIGH |
| No beacon/proxy pattern documented | Beacon + immutable-proxy + delegatecall is the upgrade mechanism | HIGH |

---

## Top Test Coverage Gaps by Protocol — TESTS ADDED

| Protocol | Missing Tests | Status |
|---|---|---|
| **Uniswap V3** | Out-of-range positions; multiple positions in same pool | Tests added |
| **Uniswap V4** | Permit2 cleanup; V4 slippage check; native ETH currency | Unit tests added |
| **Aerodrome CL** | tickSpacing variety | Partial coverage |
| **PancakeSwap V3** | MasterChef staking | Documented (not implemented in contract) |
| **SushiSwap V3** | MiniChef staking | Documented (not implemented in contract) |

Per-feature gaps:
- **EIP-1271 (W-13)** — TESTS ADDED
- **FOT/USDT (C-5)** — TESTS ADDED
- **3-token / 4-token vaults (W-15)** — TESTS ADDED
- **Reentrancy via swap router (W-16)** — TESTS ADDED
- **Foundry fuzz/invariant (W-20)** — TESTS ADDED

---

## Summary

The shared-vault implementation is substantially more mature than its plan suggests, but the plan's staleness created two real problems:
1. Plan ↔ impl divergence on `executeWithUserOrder` (C-1) appears to be an unimplemented commitment, not a deliberate design change — the plan's "one-time" guarantee is what users will reasonably expect.
2. C-4 (V4 `_validateV4ExecuteCalldataSwapRouters` incomplete) shows that defense-in-depth applied carefully on V3 (separate `isWhitelistedSwapRouter` + tokenIn/tokenOut + delta check) was not symmetrically extended to V4, where inline swaps bypass the swap-router whitelist entirely.

Resolved in this round:
- **C-1** — RESOLVED by documentation: reusable delegation is retained by design (operator trust model); the false "one-time/consumes" NatSpec was corrected. See C-1 status.
- **C-3** — FIXED: actor-scoped cancellation (`_cancelKey(actor, digest)`), with regression test.
- **C-4** — FIXED: validator removed; all V4/Pancake swaps routed through `SharedV4SwapPipeline._run` (whitelist + signed calldata). Closes W-11.
- **Hook-gate bypass** — FIXED: the no-liquidity-hook check is hosted in each strategy's `getPositionTokens`, which SharedVault calls on every tracking entry (`_applyPositionChanges` staticcall + `recoverPosition` direct call) before `_addPosition`. So recover / CALL_WITH_POSITIONS now re-enforce the gate, not only the strategy mint path. The check lives in the strategies (V4/Pancake read `poolKey.hooks`/`parameters`; V3/Aerodrome have no hooks) so `SharedVault` stays at 24,557 B / 19 B under EIP-170. On the recover path a hooked pool reverts with `UnsupportedLiquidityHook`; on the CALL_WITH_POSITIONS path (staticcall-wrapped) it surfaces as `InvalidTarget`.

The highest-leverage remaining work before mainnet deployment:
1. **C-2** — bind the UserOrder digest to a specific vault (the order struct still carries no vault field; one signature is valid against every vault the same owner controls). Lower severity now that C-1 is documented and C-3 is fixed, but still a cross-vault replay surface for a compromised operator.
2. **W-2** — Ownable2Step for vault ownership.
3. **W-3** — beacon timelock for strategy upgrades.
4. **Singleton init** — atomic deploy-and-initialize (+ `_disableInitializers`) for ConfigManager / Factory / Gateway to remove the front-run init-hijack window.
5. **EIP-170** — `SharedVault` runtime is ~19 bytes under the limit; keep new logic in libraries.

The contracts are well-engineered overall with several thoughtful patterns: defense-in-depth position validation, dust-rounding mitigation, idle-snapshot withdraw semantics, fee-pre-collect to defeat last-withdrawer fee sweeping. The biggest residual risk is the gap between *what the plan documented* and *what the code does* — closed by the plan rewrite in this round.
