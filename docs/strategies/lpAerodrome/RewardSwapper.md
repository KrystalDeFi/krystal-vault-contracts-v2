# Solidity API

## RewardSwapper

Contract for swapping farming reward tokens to principal tokens

_Manages reward token to pool mappings and handles swaps_

### Q96

```solidity
uint256 Q96
```

### Q192

```solidity
uint256 Q192
```

### configManager

```solidity
contract IConfigManager configManager
```

### poolSwapper

```solidity
contract IOptimalSwapper poolSwapper
```

### rewardTokenPools

```solidity
mapping(address => mapping(address => address)) rewardTokenPools
```

### supportedRewardTokens

```solidity
mapping(address => bool) supportedRewardTokens
```

### RewardTokenPoolSet

```solidity
event RewardTokenPoolSet(address rewardToken, address principalToken, address pool)
```

### RewardTokenSupported

```solidity
event RewardTokenSupported(address rewardToken, bool supported)
```

### RewardSwapped

```solidity
event RewardSwapped(address rewardToken, address principalToken, uint256 amountIn, uint256 amountOut, address pool)
```

### UnsupportedRewardToken

```solidity
error UnsupportedRewardToken()
```

### NoPoolConfigured

```solidity
error NoPoolConfigured()
```

### InvalidPool

```solidity
error InvalidPool()
```

### SwapFailed

```solidity
error SwapFailed()
```

### InsufficientAmountOut

```solidity
error InsufficientAmountOut()
```

### constructor

```solidity
constructor(address _configManager, address _poolSwapper, address _owner) public
```

Constructor

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _configManager | address | Address of the config manager |
| _poolSwapper | address | Address of the pool swapper |
| _owner | address | Address of the contract owner |

### setRewardTokenPool

```solidity
function setRewardTokenPool(address rewardToken, address principalToken, address pool) external
```

Set the pool for a reward token and principal token pair

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token |
| principalToken | address | Address of the principal token |
| pool | address | Address of the pool to swap through |

### setSupportedRewardToken

```solidity
function setSupportedRewardToken(address rewardToken, bool supported) external
```

Set whether a reward token is supported

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token |
| supported | bool | Whether the token is supported |

### swapRewardToPrincipal

```solidity
function swapRewardToPrincipal(address rewardToken, address principalToken, uint256 amountIn, uint256 amountOutMin, bytes swapData) external returns (uint256 amountOut)
```

Swap reward token to principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token to swap |
| principalToken | address | Address of the principal token to swap to |
| amountIn | uint256 | Amount of reward token to swap |
| amountOutMin | uint256 | Minimum amount of principal token expected |
| swapData | bytes | Additional data for the swap (router-specific) |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | Amount of principal token received |

### getAmountOut

```solidity
function getAmountOut(address rewardToken, address principalToken, uint256 amountIn) public view returns (uint256 amountOut)
```

Get the estimated output amount for swapping reward token to principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token |
| principalToken | address | Address of the principal token |
| amountIn | uint256 | Amount of reward token to swap |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | Estimated amount of principal token |

### isSwapSupported

```solidity
function isSwapSupported(address rewardToken, address principalToken) external view returns (bool supported)
```

Check if a reward token to principal token swap is supported

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token |
| principalToken | address | Address of the principal token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| supported | bool | True if the swap pair is supported |

### getPoolForPair

```solidity
function getPoolForPair(address rewardToken, address principalToken) external view returns (address pool)
```

Get the pool address for a reward-principal token pair

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token |
| principalToken | address | Address of the principal token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | address | Address of the pool for this pair |

### getRewardValue

```solidity
function getRewardValue(address rewardToken, address principalToken, uint256 amount) external view returns (uint256 value)
```

Get the value of reward token in terms of principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | Address of the reward token |
| principalToken | address | Address of the principal token |
| amount | uint256 | Amount of reward token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| value | uint256 | Value in terms of principal token |

### _getQuote

```solidity
function _getQuote(address pool, address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256 amountOut)
```

Get quote for token swap through pool

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | address | Address of the Uniswap V3 pool |
| tokenIn | address | Address of input token |
| tokenOut | address | Address of output token |
| amountIn | uint256 | Amount of input token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | Estimated amount of output token |

### _executeSwap

```solidity
function _executeSwap(address tokenIn, address tokenOut, uint256 amountIn, address pool, bytes swapData) internal
```

Execute swap through the configured pool

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenIn | address | Address of input token |
| tokenOut | address | Address of output token |
| amountIn | uint256 | Amount of input token |
| pool | address | Address of the pool |
| swapData | bytes | Additional swap data |

### emergencyRecover

```solidity
function emergencyRecover(address token, uint256 amount, address recipient) external
```

Emergency function to recover tokens

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | Address of the token to recover |
| amount | uint256 | Amount to recover |
| recipient | address | Address to send recovered tokens to |

