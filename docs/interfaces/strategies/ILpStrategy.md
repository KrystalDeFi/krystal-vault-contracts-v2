# Solidity API

## ILpStrategy

### InstructionType

```solidity
enum InstructionType {
  MintPosition,
  SwapAndMintPosition,
  IncreaseLiquidity,
  SwapAndIncreaseLiquidity,
  DecreaseLiquidity,
  DecreaseLiquidityAndSwap
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

### LpStrategyConfig

```solidity
struct LpStrategyConfig {
  uint256 principalTokenAmountMin;
  uint24 tickWidthMultiplierMin;
  uint24 tickWidthStableMultiplierMin;
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
