# Solidity API

## ILpValidator

### TokenType

```solidity
enum TokenType {
  Stable,
  Pegged
}
```

### LpStrategyConfig

```solidity
struct LpStrategyConfig {
  struct ILpValidator.LpStrategyRangeConfig[] rangeConfigs;
  struct ILpValidator.LpStrategyTvlConfig[] tvlConfigs;
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

### validateConfig

```solidity
function validateConfig(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

### validateTickWidth

```solidity
function validateTickWidth(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
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

