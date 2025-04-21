# Solidity API

## LpFeeTaker

### Q64

```solidity
uint256 Q64
```

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

### pancakeV3SwapCallback

```solidity
function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes) external
```

Callback function required by Pancake V3 to finalize swaps

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0Delta | int256 | The change in token0 balance |
| amount1Delta | int256 | The change in token1 balance |
|  | bytes |  |

### SwapToPrincipalParams

```solidity
struct SwapToPrincipalParams {
  address pool;
  address principalToken;
  address token;
  uint256 amount;
  uint256 amountOutMin;
  bytes swapData;
}
```

### takeFees

```solidity
function takeFees(address token0, uint256 amount0, address token1, uint256 amount1, struct ICommon.FeeConfig feeConfig, address principalToken, address pool, address validator) external returns (uint256 fee0, uint256 fee1)
```

### _takeFee

```solidity
function _takeFee(uint256 amount, struct ICommon.FeeConfig feeConfig) internal pure returns (uint256 totalFeeAmount, uint256 platformFeeAmount, uint256 vaultOwnerFeeAmount, uint256 gasFeeAmount)
```

_Takes the fee from the amount_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | The amount to take the fee |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| totalFeeAmount | uint256 | The total fee amount |
| platformFeeAmount | uint256 |  |
| vaultOwnerFeeAmount | uint256 |  |
| gasFeeAmount | uint256 |  |

### _swapToPrincipal

```solidity
function _swapToPrincipal(struct LpFeeTaker.SwapToPrincipalParams params, contract ILpValidator validator) internal returns (uint256 amountOut, uint256 amountInUsed)
```

Swaps the token to the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct LpFeeTaker.SwapToPrincipalParams | The parameters for swapping the token |
| validator | contract ILpValidator |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | The result amount of principal token |
| amountInUsed | uint256 | The amount of token used |

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

