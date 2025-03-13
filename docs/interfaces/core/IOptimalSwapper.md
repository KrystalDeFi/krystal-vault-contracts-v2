# Solidity API

## IOptimalSwapper

### OptimalSwapParams

```solidity
struct OptimalSwapParams {
  address pool;
  uint256 amount0Desired;
  uint256 amount1Desired;
  int24 tickLower;
  int24 tickUpper;
  bytes data;
}
```

### optimalSwap

```solidity
function optimalSwap(struct IOptimalSwapper.OptimalSwapParams params) external returns (uint256 amount0Result, uint256 amount1Result)
```

### getOptimalSwapAmounts

```solidity
function getOptimalSwapAmounts(address pool, uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper, bytes data) external view returns (uint256 amount0, uint256 amount1)
```

### poolSwap

```solidity
function poolSwap(address pool, uint256 amountIn, bool zeroToOne, uint256 amountOutMin, bytes data) external returns (uint256 amountOut, uint256 amountInUsed)
```

