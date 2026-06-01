# Solidity API

## SharedStrategyFees

Canonical fee-application model for the shared-vault strategies (V3, Aerodrome, V4, PancakeV4).
        Replaces the public-vault `LpFeeTaker` for shared strategies: instead of swapping the
        non-principal fee slice into a single "principal" token, it transfers the platform /
        vault-owner / gas fee slices of token0 and token1 DIRECTLY to their recipients. Both fee
        recipients (platform + vault owner) accept any of the vault's tokens, so no swap, price
        validation, or pool interaction is needed — the previous `LpFeeTaker` swap path was redundant.

_Runs in the vault's context (the strategies/libs that call this are delegatecalled by SharedVault),
     so `address(this)` is the vault and the fee tokens are pulled from the vault's idle balance.

     Fees are applied SEQUENTIALLY against a running remainder (platform → owner → gas). Each share is
     computed from the ORIGINAL amount and clamped to whatever is left (`if (fee > remaining) fee =
     remaining`). Because every share is computed from the original amount, the clamp only ever caps the
     LAST fee type(s) when the configured bps sum exceeds 100% — total fee can NEVER exceed the collected
     amount, so the `collected - fee` accounting downstream can never underflow. This is the same model
     the V4/Pancake libs apply inline, now unified across every shared strategy, eliminating the previous
     revert-vs-clamp divergence (V3/Aerodrome used to route through `LpFeeTaker`, which summed fees without
     clamping and therefore needed an explicit `platform+owner+gas <= 100%` revert guard). `gasFeeX64` is a
     Q64 fraction and, like platform/owner bps, is clamped rather than reverted._

### FeeCollected

```solidity
event FeeCollected(address vaultAddress, enum IFeeTaker.FeeType feeType, address recipient, address token, uint256 amount)
```

### applyFees

```solidity
function applyFees(address token0, uint256 amount0, address token1, uint256 amount1, struct ICommon.FeeConfig fc) internal returns (uint256 feeTaken0, uint256 feeTaken1)
```

Apply platform/owner/gas fees to (token0, amount0) and (token1, amount1), transferring each fee
        slice directly to its recipient.

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| feeTaken0 | uint256 | Total fee taken from token0 (platform + owner + gas), always <= amount0 |
| feeTaken1 | uint256 | Total fee taken from token1 (platform + owner + gas), always <= amount1 |

