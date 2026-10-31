# Solidity API

## IRamsesV3Pool

The state of a Ramses CL pool the vault strategies value positions with. `slot0` has 7 fields with a
        uint24 `feeProtocol` (FEE_DENOM 1e6) and `ticks` keeps Uniswap V3's 8-field layout, unlike Slipstream's.

### slot0

```solidity
function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint24 feeProtocol, bool unlocked)
```

### ticks

```solidity
function ticks(int24 tick) external view returns (uint128 liquidityGross, int128 liquidityNet, uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, int56 tickCumulativeOutside, uint160 secondsPerLiquidityOutsideX128, uint32 secondsOutside, bool initialized)
```

### feeGrowthGlobal0X128

```solidity
function feeGrowthGlobal0X128() external view returns (uint256)
```

### feeGrowthGlobal1X128

```solidity
function feeGrowthGlobal1X128() external view returns (uint256)
```

