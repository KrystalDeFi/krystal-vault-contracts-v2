# Solidity API

## PancakeV4PositionInfo

## PancakeV4PositionInfoLibrary

### TICK_LOWER_OFFSET

```solidity
uint8 TICK_LOWER_OFFSET
```

### TICK_UPPER_OFFSET

```solidity
uint8 TICK_UPPER_OFFSET
```

### tickLower

```solidity
function tickLower(PancakeV4PositionInfo info) internal pure returns (int24 tick)
```

### tickUpper

```solidity
function tickUpper(PancakeV4PositionInfo info) internal pure returns (int24 tick)
```

## PancakeV4PoolKeyLibrary

### toId

```solidity
function toId(struct PancakeV4PoolKey poolKey) internal pure returns (bytes32 poolId)
```

## PancakeV4TickInfo

```solidity
struct PancakeV4TickInfo {
  uint128 liquidityGross;
  int128 liquidityNet;
  uint256 feeGrowthOutside0X128;
  uint256 feeGrowthOutside1X128;
}
```

## IPancakeV4CLPoolManager

### initialize

```solidity
function initialize(struct PancakeV4PoolKey key, uint160 sqrtPriceX96) external returns (int24 tick)
```

### getSlot0

```solidity
function getSlot0(bytes32 id) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
```

### getFeeGrowthGlobals

```solidity
function getFeeGrowthGlobals(bytes32 id) external view returns (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128)
```

### getPoolTickInfo

```solidity
function getPoolTickInfo(bytes32 id, int24 tick) external view returns (struct PancakeV4TickInfo)
```

## IPancakeV4PositionManager

### clPoolManager

```solidity
function clPoolManager() external view returns (address)
```

### permit2

```solidity
function permit2() external view returns (address)
```

### modifyLiquidities

```solidity
function modifyLiquidities(bytes payload, uint256 deadline) external payable
```

### nextTokenId

```solidity
function nextTokenId() external view returns (uint256)
```

### getPositionLiquidity

```solidity
function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity)
```

### getPoolAndPositionInfo

```solidity
function getPoolAndPositionInfo(uint256 tokenId) external view returns (struct PancakeV4PoolKey poolKey, PancakeV4PositionInfo info)
```

### positions

```solidity
function positions(uint256 tokenId) external view returns (struct PancakeV4PoolKey poolKey, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, address subscriber)
```

