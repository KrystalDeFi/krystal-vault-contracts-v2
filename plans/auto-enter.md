# Auto-Enter — krystal-vault-contracts-v2 Implementation Plan

> **This is one of 5 coordinated per-repo plans.** Master plan: `/Users/maddie/.claude/plans/i-want-to-implement-elegant-sky.md`. Sister plans:
> - `krystal-services/plans/auto-enter.md`
> - `krystal-web/plans/auto-enter.md`
> - `v3utils/plans/auto-enter.md`
> - `v4utils/plans/auto-enter.md`

## 0. Verdict — ZERO Solidity changes

The existing infrastructure already supports vault-mode auto-enter:
- `contracts/private-vault/core/PrivateVaultAutomator.sol::executeMulticallWithAgentAllowance` — accepts arbitrary multicall payloads gated by `AgentAllowance` (off-chain EIP-712 signed by vault owner).
- `contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol::swapAndMint` — overwrites `params.recipient = address(this)`, so the position NFT lands on the vault.
- `contracts/private-vault/strategies/lpv4/V4UtilsStrategy.sol::execute` — same shape for v4.

This plan is therefore a **CONTRACT SPECIFICATION** so the backend (krystal-services) and the worker know exactly how to construct the multicall payload. **No Solidity to write or deploy** in this repo for v1.

## 1. Scope

For vault-mode auto-enter:
- User has an existing Krystal Private Vault.
- User has already signed an `AgentAllowance` for the backend worker (signature persisted in cesar-app / cloud-api today).
- Worker constructs a multicall payload and submits via `executeMulticallWithAgentAllowance`.
- Follow-up automations (auto-compound / auto-rebalance / auto-exit / auto-harvest) require no extra signatures — the same AgentAllowance umbrella covers them.

## 2. The multicall payload contract (verbatim)

### 2.1 v3 vault mint

```solidity
targets    = [ V3UtilsStrategy_addr ]
callValues = [ ethValueIfNative ]   // 0 for ERC20-only funding
data       = [ abi.encodeWithSelector(
    V3UtilsStrategy.swapAndMint.selector,
    IV3Utils.SwapAndMintParams({
      protocol:        Nfpm.Protocol.UNI_V3,
      nfpm:            nfpmAddr,
      token0:          IERC20(targetToken0),
      token1:          IERC20(targetToken1),
      fee:             feeTier,
      tickSpacing:     tickSpacing,
      tickLower:       order.action.tickLower,
      tickUpper:       order.action.tickUpper,
      protocolFeeX64:  order.action.protocolFeeX64,
      gasFeeX64:       order.action.gasFeeX64,
      amount0:         0,
      amount1:         0,
      amount2:         order.action.sourceAmount,    // single-token funding
      recipient:       address(0),                   // strategy overwrites with vault
      deadline:        block.timestamp + window,
      swapSourceToken: IERC20(order.action.sourceToken),
      amountIn0:       computedIn0,
      amountOut0Min:   computedMin0,
      swapData0:       backendSwapData0,             // 0x routes
      amountIn1:       computedIn1,
      amountOut1Min:   computedMin1,
      swapData1:       backendSwapData1,
      amountAddMin0:   liquidityFloor0,
      amountAddMin1:   liquidityFloor1,
      poolDeployer:    address(0)
    }),
    0,                              // ethValue (re-asserted inside strategy)
    [order.action.sourceToken],     // tokens vault must approve to V3Utils
    [order.action.sourceAmount],    // approval amounts
    true                            // returnLeftoverToOwner
  ) ]
callTypes  = [ CallType.STRATEGY ]
```

### 2.2 v4 vault mint

```solidity
targets    = [ V4UtilsStrategy_addr ]
callValues = [ ethValueIfNative ]
data       = [ abi.encodeWithSelector(
    V4UtilsStrategy.execute.selector,
    posm,                           // PositionManager
    uint256(0),                     // tokenId = 0 ⇒ MINT path
    abi.encodeWithSelector(
      V4UtilsRouter.execute.selector,
      posm,
      abi.encodeWithSelector(
        IV4Utils.swapAndMint.selector,
        IV4Utils.SwapAndMintParams({
          posm:            posm,
          poolKey:         PoolKey(currency0, currency1, fee, tickSpacing, hooks),
          mintParams:      IV4Utils.MintParams({
            tickLower: tickLower, tickUpper: tickUpper,
            minLiquidity: minLiq, hookData: hookData, deadline: deadline
          }),
          inputTokens:     [InputTokenParams(Currency.wrap(sourceToken), sourceAmount)],
          swapParams:      [swapParams...],
          sweepTokens:     [Currency.wrap(sourceToken)],
          protocolFeeX64:  protocolFeeX64,
          gasFeeX64:       gasFeeX64,
          performanceFeeX64: 0
        })
      )
    ),
    ethValueIfNative,
    [sourceToken],
    [sourceAmount],
    true                            // returnLeftoverToOwner
  ) ]
callTypes  = [ CallType.STRATEGY ]
```

### 2.3 AgentAllowance reuse

`PrivateVaultAutomator.executeMulticallWithAgentAllowance(vault, targets, callValues, data, callTypes, agentAllowanceEncoded, agentSignature)`:
- `agentAllowanceEncoded` = `abi.encode(AgentAllowance({vault, signatureTime, expirationTime}))`
- `agentSignature` = EIP-712 signature by vault owner against domain `"V3AutomationOrder"` v5.0, type-hash `AgentAllowance(address vault,uint64 signatureTime,uint64 expirationTime)`.

The AgentAllowance domain remains **v5.0** — the AgentAllowance type-hash hasn't changed and existing signatures continue to work for AUTO_ENTER's vault mode. **Do not bump AgentAllowance to v6.**

### 2.4 Post-mint reconciliation

After the multicall executes, the position NFT belongs to the vault. Backend extracts the minted tokenId from:
- **v3**: receipt log `IncreaseLiquidity(uint256 indexed tokenId, ...)` emitted by NFPM. tokenId = `topic[1]`.
- **v4**: receipt log `Transfer(address indexed from, address indexed to, uint256 indexed tokenId)` from posm where `from == address(0)`. tokenId = `topic[3]`.

Follow-up orders (if any) get the same tokenId written to their template row. No further on-chain action needed — follow-ups execute via the same `executeMulticallWithAgentAllowance` path with different multicall data targeting the rebalance/compound/exit strategies.

## 3. What's intentionally NOT in v1

- **Scoped AgentAllowance**: current AgentAllowance is coarse-grained (any whitelisted strategy until expiry). A future `ScopedAgentAllowance` could restrict to specific (target, selector, amount-ceiling) tuples. Out of scope; the umbrella model is acceptable per the existing vault trust model.
- **Per-multicall signature** (separate from AgentAllowance): no — would defeat the purpose of pre-authorizing the agent.
- **New strategies**: V3UtilsStrategy and V4UtilsStrategy already cover v3 and v4 mints. No new strategies needed.

## 4. Recommended integration test (optional, in this repo)

Add a single Foundry test under `test/integration/AutoEnterMulticall.t.sol` that:
1. Constructs the exact payload from §2.1 / §2.2 (mirroring backend's encoder output).
2. Forks a chain with V3UtilsStrategy/V4UtilsStrategy deployed.
3. Funds a vault with USDC.
4. Calls `PrivateVaultAutomator.executeMulticallWithAgentAllowance` with a valid AgentAllowance signature.
5. Asserts the vault now owns a new position NFT with the correct ticks and liquidity.

This protects against backend's payload encoder drifting from the strategy's expected ABI shape. Recommend pinning the payload encoder in `helpers/` as a TypeScript fixture that both backend and this test consume.

## 5. Files

This repo: **no new files, no modified files** for v1. The `test/integration/AutoEnterMulticall.t.sol` test is recommended but optional.

## 6. Coordination notes

When backend implementation lands:
- Confirm `V3UtilsStrategy.sol` line 48 (or current location) still has `params.recipient = address(this);` hard-coded. If the strategy is updated to take recipient from caller, backend must explicitly set `recipient = vaultAddress`.
- Confirm `V4UtilsStrategy.execute` similarly sweeps the resulting NFT into the vault.
- Confirm V3UtilsStrategy / V4UtilsStrategy are whitelisted as STRATEGY targets in each vault deployment. If not, vaults need to be configured per the existing whitelist mechanism.

## 7. Future work (Phase 2+)

- **Scoped AgentAllowance** (described above).
- **Dynamic pool selection** for vault auto-enter: backend picks a target pool from a filter (top APR / pair whitelist) at trigger time. Vault contracts don't need to know about the filter — just receive the resolved pool in the multicall payload. The user's authorization is the AgentAllowance umbrella.
- **Cross-strategy follow-up sequencing**: post-mint multicall that immediately rebalances or compounds within the same vault tx. Could compress two transactions into one. Requires careful gas budgeting.
