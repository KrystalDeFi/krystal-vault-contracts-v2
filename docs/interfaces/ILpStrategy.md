# Solidity API

## ILpStrategy

### InstructionType

```solidity
enum InstructionType {
  MintPosition,
  IncreaseLiquidity,
  DecreaseLiquidity
}
```

### Instruction

```solidity
struct Instruction {
  enum ILpStrategy.InstructionType instructionType;
  bytes params;
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

### IncreaseLiquidityParams

```solidity
struct IncreaseLiquidityParams {
  uint256 amount0Min;
  uint256 amount1Min;
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

