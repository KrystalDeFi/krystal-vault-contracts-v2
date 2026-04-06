# Solidity API

## SharedNfpmProportionalExit

Mirrors public `LpStrategy._decreaseLiquidity`: collect accrued fees → `LpFeeTaker.takeFees` (perf/platform) →
        decrease proportional liquidity → collect principal → optional gas fee on principal via `LpFeeTaker`.

### decreaseLiquidityProportional

```solidity
function decreaseLiquidityProportional(address nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 amount0Min, uint256 amount1Min, address token0, address token1, address pool, address lpFeeTaker, struct ICommon.FeeConfig perfFeeConfig) internal
```

_Pulls performance/platform/owner fees from collected fee amounts; gas fee is taken from principal after decrease (public pattern)._

