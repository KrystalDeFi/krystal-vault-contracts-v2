# Solidity API

## OptimalSwap

Optimal library for optimal double-sided Uniswap v3 liquidity provision using closed form solution

### MAX_FEE_PIPS

```solidity
uint256 MAX_FEE_PIPS
```

### Invalid_Pool

```solidity
error Invalid_Pool()
```

### Invalid_Tick_Range

```solidity
error Invalid_Tick_Range()
```

### Math_Overflow

```solidity
error Math_Overflow()
```

### SwapState

```solidity
struct SwapState {
  uint128 liquidity;
  uint256 sqrtPriceX96;
  int24 tick;
  uint256 amount0Desired;
  uint256 amount1Desired;
  uint256 sqrtRatioLowerX96;
  uint256 sqrtRatioUpperX96;
  uint256 feePips;
  int24 tickSpacing;
}
```

### getOptimalSwap

```solidity
function getOptimalSwap(V3PoolCallee pool, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired) internal view returns (uint256 amountIn, uint256 amountOut, bool zeroForOne, uint160 sqrtPriceX96)
```

Get swap amount, output amount, swap direction for double-sided optimal deposit

_Given the elegant analytic solution and custom optimizations to Uniswap libraries, the amount of gas is at the order of
10k depending on the swap amount and the number of ticks crossed, an order of magnitude less than that achieved by
binary search, which can be calculated on-chain._

#### Parameters

| Name           | Type         | Description                                              |
| -------------- | ------------ | -------------------------------------------------------- |
| pool           | V3PoolCallee | Uniswap v3 pool                                          |
| tickLower      | int24        | The lower tick of the position in which to add liquidity |
| tickUpper      | int24        | The upper tick of the position in which to add liquidity |
| amount0Desired | uint256      | The desired amount of token0 to be spent                 |
| amount1Desired | uint256      | The desired amount of token1 to be spent                 |

#### Return Values

| Name         | Type    | Description                                                                      |
| ------------ | ------- | -------------------------------------------------------------------------------- |
| amountIn     | uint256 | The optimal swap amount                                                          |
| amountOut    | uint256 | Expected output amount                                                           |
| zeroForOne   | bool    | The direction of the swap, true for token0 to token1, false for token1 to token0 |
| sqrtPriceX96 | uint160 | The sqrt(price) after the swap                                                   |

### isZeroForOne

```solidity
function isZeroForOne(uint256 amount0Desired, uint256 amount1Desired, uint256 sqrtPriceX96, uint256 sqrtRatioLowerX96, uint256 sqrtRatioUpperX96) internal pure returns (bool)
```

_Swap direction to achieve optimal deposit_

#### Parameters

| Name              | Type    | Description                                                     |
| ----------------- | ------- | --------------------------------------------------------------- |
| amount0Desired    | uint256 | The desired amount of token0 to be spent                        |
| amount1Desired    | uint256 | The desired amount of token1 to be spent                        |
| sqrtPriceX96      | uint256 | sqrt(price) at the last tick of optimal swap                    |
| sqrtRatioLowerX96 | uint256 | The lower sqrt(price) of the position in which to add liquidity |
| sqrtRatioUpperX96 | uint256 | The upper sqrt(price) of the position in which to add liquidity |

#### Return Values

| Name | Type | Description                                                                      |
| ---- | ---- | -------------------------------------------------------------------------------- |
| [0]  | bool | The direction of the swap, true for token0 to token1, false for token1 to token0 |
