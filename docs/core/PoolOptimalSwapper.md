# Solidity API

## PoolOptimalSwapper

### MAX_SQRT_RATIO_LESS_ONE

```solidity
uint160 MAX_SQRT_RATIO_LESS_ONE
```

### XOR_SQRT_RATIO

```solidity
uint160 XOR_SQRT_RATIO
```

### uniswapV3SwapCallback

```solidity
function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes) external
```

Callback function required by Uniswap V3 to finalize swaps

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0Delta | int256 | The change in token0 balance |
| amount1Delta | int256 | The change in token1 balance |
|  | bytes |  |

### _poolSwap

```solidity
function _poolSwap(address pool, uint256 amountIn, bool zeroForOne) internal returns (uint256 amountOut, uint256 amountInUsed)
```

_Make a direct `exactIn` pool swap_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | address | The address of the Uniswap V3 pool |
| amountIn | uint256 | The amount of token to be swapped |
| zeroForOne | bool | The direction of the swap, true for token0 to token1, false for token1 to token0 |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | The amount of token received after swap |
| amountInUsed | uint256 | The amount of token used for swap |

### optimalSwap

```solidity
function optimalSwap(struct IOptimalSwapper.OptimalSwapParams params) external returns (uint256 amount0, uint256 amount1)
```

Swap tokens in a Uniswap V3 pool

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct IOptimalSwapper.OptimalSwapParams | The parameters for the optimal swap |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The amount of token0 received after swap |
| amount1 | uint256 | The amount of token1 received after swap |

### getOptimalSwapAmounts

```solidity
function getOptimalSwapAmounts(address pool, uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper, bytes) external view returns (uint256 amount0, uint256 amount1)
```

Get the optimal swap amounts for a given pool

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | address | The address of the Uniswap V3 pool |
| amount0Desired | uint256 | The desired amount of token0 |
| amount1Desired | uint256 | The desired amount of token1 |
| tickLower | int24 | The lower tick of the pool |
| tickUpper | int24 | The upper tick of the pool |
|  | bytes |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The optimal amount of token0 to swap |
| amount1 | uint256 | The optimal amount of token1 to swap |

### poolSwap

```solidity
function poolSwap(address pool, uint256 amountIn, bool zeroForOne, uint256 amountOutMin, bytes) external returns (uint256 amountOut, uint256 amountInUsed)
```

Swap exactIn tokens through an UniswapV3Pool

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | address | The address of the Uniswap V3 pool |
| amountIn | uint256 | The amount of token to be swapped |
| zeroForOne | bool | The direction of the swap, true for token0 to token1, false for token1 to token0 |
| amountOutMin | uint256 | The minimum amount of token to receive after swap |
|  | bytes |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | The amount of token received after swap |
| amountInUsed | uint256 | The amount of token used for swap |

