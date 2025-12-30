# Solidity API

## IUniswapV3Pool

### slot0

```solidity
function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint32 feeProtocol, bool unlocked)
```

### positions

```solidity
function positions(bytes32 _positionId) external view returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1)
```

### feeGrowthGlobal0X128

```solidity
function feeGrowthGlobal0X128() external view returns (uint256)
```

### feeGrowthGlobal1X128

```solidity
function feeGrowthGlobal1X128() external view returns (uint256)
```

### ticks

```solidity
function ticks(int24 _tick) external view returns (uint128 liquidityGross, int128 liquidityNet, uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, int56 tickCumulativeOutside, uint160 secondsPerLiquidityOutsideX128, uint32 secondsOutside, bool initialized)
```

## IKodiakIsland

### mint

```solidity
function mint(uint256 mintAmount, address receiver) external returns (uint256 amount0, uint256 amount1, uint128 liquidityMinted)
```

### burn

```solidity
function burn(uint256 burnAmount, address receiver) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned)
```

### getUnderlyingBalancesAtPrice

```solidity
function getUnderlyingBalancesAtPrice(uint160 sqrtRatioX96) external view returns (uint256 amount0Current, uint256 amount1Current)
```

### manager

```solidity
function manager() external view returns (address)
```

### getMintAmounts

```solidity
function getMintAmounts(uint256 amount0Max, uint256 amount1Max) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount)
```

### getUnderlyingBalances

```solidity
function getUnderlyingBalances() external view returns (uint256 amount0, uint256 amount1)
```

### getPositionID

```solidity
function getPositionID() external view returns (bytes32 positionID)
```

### token0

```solidity
function token0() external view returns (contract IERC20)
```

### token1

```solidity
function token1() external view returns (contract IERC20)
```

### upperTick

```solidity
function upperTick() external view returns (int24)
```

### lowerTick

```solidity
function lowerTick() external view returns (int24)
```

### pool

```solidity
function pool() external view returns (contract IUniswapV3Pool)
```

### totalSupply

```solidity
function totalSupply() external view returns (uint256)
```

### balanceOf

```solidity
function balanceOf(address account) external view returns (uint256)
```

### managerFeeBPS

```solidity
function managerFeeBPS() external view returns (uint16)
```

### islandFactory

```solidity
function islandFactory() external view returns (address)
```

