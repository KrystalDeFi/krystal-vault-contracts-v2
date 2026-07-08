# Solidity API

## SharedNfpmProportionalExit

Pre-collect accrued fees → take perf/platform fees → decrease proportional liquidity → collect
        principal. Fees are settled via `SharedStrategyFees` (direct proportional transfer of each token's
        fee slice to platform / vault owner), NOT the public-vault `LpFeeTaker` swap-and-consolidate path.

### collectAccumulatedFees

```solidity
function collectAccumulatedFees(address nfpm, uint256 tokenId, address token0, address token1, struct ICommon.FeeConfig perfFeeConfig) internal
```

Pre-collect accrued fees into vault idle balance and take perf/platform fees.

_Called from strategy.collectFees() which is delegatecalled by SharedVault.withdraw() BEFORE
     the idleBefore snapshot so that accumulated fees are distributed proportionally by share ratio.

     **Fee-sync safety**: Both the canonical Uniswap V3 NFPM and Slipstream/Aerodrome NFPM call
     `pool.burn(tickLower, tickUpper, 0)` inside their `collect()` implementations when
     `position.liquidity > 0`. This pool call updates `feeGrowthInsideLast*` and computes the
     pending fee-growth delta into `tokensOwed*`, so `collect(type(uint128).max, type(uint128).max)`
     here captures ALL accrued fees — both the previously-synced `tokensOwed*` stored on the NFT
     and any fee growth that accumulated since the last sync. No separate pre-sync step is needed.

     Because this function and the subsequent `decreaseLiquidityProportional` run in the same
     transaction, zero additional swap fees can accrue between them, so the withdrawer cannot
     receive fees beyond their proportional share via the later `collect(type(uint128).max)`._

### decreaseLiquidityProportional

```solidity
function decreaseLiquidityProportional(address nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 amount0Min, uint256 amount1Min, address token0, address token1, struct ICommon.FeeConfig perfFeeConfig) internal
```

_Fees are pre-collected by `collectAccumulatedFees` before the idle snapshot in SharedVault.withdraw(),
     so this function only decreases liquidity, collects the resulting principal, and (when configured)
     takes a gas fee on the principal. On the withdraw/exit path `performanceFeeConfig()` sets
     `gasFeeX64 = 0`, so the gas branch is inert there; it remains for callers that pass a gas fee._

