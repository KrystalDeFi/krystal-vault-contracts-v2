# Solidity API

## ILpValidator

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
  int24 tickWidthMin;
  int24 tickWidthTypedMin;
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
function validateTickWidth(address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

### validateObservationCardinality

```solidity
function validateObservationCardinality(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1) external view
```

### validatePriceSanity

```solidity
function validatePriceSanity(address pool) external view
```

### InvalidPool

```solidity
error InvalidPool()
```

### InvalidPoolAmountMin

```solidity
error InvalidPoolAmountMin()
```

### InvalidTickWidth

```solidity
error InvalidTickWidth()
```

### InvalidObservationCardinality

```solidity
error InvalidObservationCardinality()
```

### InvalidObservation

```solidity
error InvalidObservation()
```

### PriceSanityCheckFailed

```solidity
error PriceSanityCheckFailed()
```

