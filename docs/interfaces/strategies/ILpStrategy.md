# Solidity API

## ILpStrategy

### InstructionType

```solidity
enum InstructionType {
  MintPosition,
  SwapAndMintPosition,
  IncreaseLiquidity,
  SwapAndIncreaseLiquidity,
  DecreaseLiquidityAndSwap,
  SwapAndRebalancePosition,
  SwapAndCompound
}
```

### TokenType

```solidity
enum TokenType {
  Stable,
  Pegged
}
```

### MintPositionParams

```solidity
struct MintPositionParams {
  contract INonfungiblePositionManager nfpm;
  address token0;
  address token1;
  uint24 fee;
  int24 tickLower;
  int24 tickUpper;
  uint256 amount0Min;
  uint256 amount1Min;
}
```

### SwapAndMintPositionParams

```solidity
struct SwapAndMintPositionParams {
  contract INonfungiblePositionManager nfpm;
  address token0;
  address token1;
  uint24 fee;
  int24 tickLower;
  int24 tickUpper;
  uint256 amount0Min;
  uint256 amount1Min;
  bytes swapData;
}
```

### IncreaseLiquidityParams

```solidity
struct IncreaseLiquidityParams {
  uint256 amount0Min;
  uint256 amount1Min;
}
```

### SwapAndIncreaseLiquidityParams

```solidity
struct SwapAndIncreaseLiquidityParams {
  uint256 amount0Min;
  uint256 amount1Min;
  bytes swapData;
}
```

### DecreaseLiquidityParams

```solidity
struct DecreaseLiquidityParams {
  uint128 liquidity;
  uint256 amount0Min;
  uint256 amount1Min;
}
```

### DecreaseLiquidityAndSwapParams

```solidity
struct DecreaseLiquidityAndSwapParams {
  uint128 liquidity;
  uint256 amount0Min;
  uint256 amount1Min;
  uint256 principalAmountOutMin;
  bytes swapData;
}
```

### SwapAndRebalancePositionParams

```solidity
struct SwapAndRebalancePositionParams {
  int24 tickLower;
  int24 tickUpper;
  uint256 decreasedAmount0Min;
  uint256 decreasedAmount1Min;
  uint256 amount0Min;
  uint256 amount1Min;
  bool compoundFee;
  bytes swapData;
}
```

### SwapAndCompoundParams

```solidity
struct SwapAndCompoundParams {
  uint256 amount0Min;
  uint256 amount1Min;
  bytes swapData;
}
```

### SwapFromPrincipalParams

```solidity
struct SwapFromPrincipalParams {
  uint256 principalTokenAmount;
  address pool;
  address principalToken;
  address otherToken;
  int24 tickLower;
  int24 tickUpper;
  bytes swapData;
}
```

### SwapToPrincipalParams

```solidity
struct SwapToPrincipalParams {
  address pool;
  address principalToken;
  address token;
  uint256 amount;
  uint256 amountOutMin;
  bytes swapData;
}
```

### LpStrategyConfig

```solidity
struct LpStrategyConfig {
  struct ILpStrategy.LpStrategyRangeConfig[] rangeConfigs;
  struct ILpStrategy.LpStrategyTvlConfig[] tvlConfigs;
}
```

### LpStrategyRangeConfig

```solidity
struct LpStrategyRangeConfig {
  uint24 tickWidthMultiplierMin;
  uint24 tickWidthStableMultiplierMin;
}
```

### LpStrategyTvlConfig

```solidity
struct LpStrategyTvlConfig {
  uint256 principalTokenAmountMin;
}
```

### InvalidPool

```solidity
error InvalidPool()
```

### InvalidPoolAmountAmountMin

```solidity
error InvalidPoolAmountAmountMin()
```

### InvalidTickWidth

```solidity
error InvalidTickWidth()
```

