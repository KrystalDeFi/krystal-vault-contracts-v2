# Solidity API

## SharedNfpmProportionalExit

Mirrors public `LpStrategy._decreaseLiquidity`: collect accrued fees → `LpFeeTaker.takeFees` (perf/platform) →
        decrease proportional liquidity → collect principal → optional gas fee on principal via `LpFeeTaker`.

### collectAccumulatedFees

```solidity
function collectAccumulatedFees(address nfpm, uint256 tokenId, address token0, address token1, address pool, address lpFeeTaker, struct ICommon.FeeConfig perfFeeConfig) internal
```

Pre-collect accrued fees into vault idle balance and take perf/platform fees.

_Called from strategy.collectFees() which is delegatecalled by SharedVault.withdraw() BEFORE
     the idleBefore snapshot so that accumulated fees are distributed proportionally by share ratio._

### decreaseLiquidityProportional

```solidity
function decreaseLiquidityProportional(address nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 amount0Min, uint256 amount1Min, address token0, address token1, address pool, address lpFeeTaker, struct ICommon.FeeConfig perfFeeConfig) internal
```

_Pulls performance/platform/owner fees from collected fee amounts; gas fee is taken from principal after decrease (public pattern).
     Fees are pre-collected by `collectAccumulatedFees` before the idle snapshot in SharedVault.withdraw(),
     so this function only decreases liquidity and collects the resulting principal._

