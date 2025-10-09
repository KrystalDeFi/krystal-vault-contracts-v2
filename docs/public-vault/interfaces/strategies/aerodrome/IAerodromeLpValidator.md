# Solidity API

## IAerodromeLpValidator

### LpStrategyConfig

```solidity
struct LpStrategyConfig {
  struct IAerodromeLpValidator.LpStrategyRangeConfig[] rangeConfigs;
  struct IAerodromeLpValidator.LpStrategyTvlConfig[] tvlConfigs;
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
function validateConfig(contract INonfungiblePositionManager nfpm, int24 tickSpacing, address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

### validateTickWidth

```solidity
function validateTickWidth(address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

### validateObservationCardinality

```solidity
function validateObservationCardinality(contract INonfungiblePositionManager nfpm, int24 tickSpacing, address token0, address token1) external view
```

### validatePriceSanity

```solidity
function validatePriceSanity(address pool) external view
```

### validateNfpm

```solidity
function validateNfpm(address nfpm) external view
```

### InvalidPool

```solidity
error InvalidPool()
```

### InvalidNfpm

```solidity
error InvalidNfpm()
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

