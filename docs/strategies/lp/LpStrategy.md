# Solidity API

## LpStrategy

### optimalSwapper

```solidity
contract IOptimalSwapper optimalSwapper
```

### configManager

```solidity
contract IConfigManager configManager
```

### constructor

```solidity
constructor(address _optimalSwapper, address _configManager) public
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset, address principalToken) external view returns (uint256 valueInPrincipal)
```

Get value of the asset in terms of principalToken

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to get the value |
| principalToken | address |  |

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig vaultConfig, bytes data) external returns (struct AssetLib.Asset[] returnAssets)
```

Converts the asset to another assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to convert |
| vaultConfig | struct ICommon.VaultConfig |  |
| data | bytes | The data for the instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut) external returns (struct AssetLib.Asset[] returnAssets)
```

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig vaultConfig) external returns (struct AssetLib.Asset[] returnAssets)
```

### mintPosition

```solidity
function mintPosition(struct AssetLib.Asset[] assets, struct ILpStrategy.MintPositionParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Mints a new position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to mint the position, assets[0] = token0, assets[1] = token1 |
| params | struct ILpStrategy.MintPositionParams | The parameters for minting the position |
| vaultConfig | struct ICommon.VaultConfig |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### swapAndMintPosition

```solidity
function swapAndMintPosition(struct AssetLib.Asset[] assets, struct ILpStrategy.SwapAndMintPositionParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _mintPosition

```solidity
function _mintPosition(struct AssetLib.Asset[] assets, struct ILpStrategy.MintPositionParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

### increaseLiquidity

```solidity
function increaseLiquidity(struct AssetLib.Asset[] assets, struct ILpStrategy.IncreaseLiquidityParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Increases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to increase the liquidity assets[2] = lpAsset |
| params | struct ILpStrategy.IncreaseLiquidityParams | The parameters for increasing the liquidity |
| vaultConfig | struct ICommon.VaultConfig |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### swapAndIncreaseLiquidity

```solidity
function swapAndIncreaseLiquidity(struct AssetLib.Asset[] assets, struct ILpStrategy.SwapAndIncreaseLiquidityParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _increaseLiquidity

```solidity
function _increaseLiquidity(struct AssetLib.Asset[] assets, struct ILpStrategy.IncreaseLiquidityParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

### decreaseLiquidity

```solidity
function decreaseLiquidity(struct AssetLib.Asset[] assets, struct ILpStrategy.DecreaseLiquidityParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

Decreases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to decrease the liquidity assets[0] = lpAsset |
| params | struct ILpStrategy.DecreaseLiquidityParams | The parameters for decreasing the liquidity |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### decreaseLiquidityAndSwap

```solidity
function decreaseLiquidityAndSwap(struct AssetLib.Asset[] assets, struct ILpStrategy.DecreaseLiquidityAndSwapParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _decreaseLiquidity

```solidity
function _decreaseLiquidity(struct AssetLib.Asset lpAsset, struct ILpStrategy.DecreaseLiquidityParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _optimalSwapFromPrincipal

```solidity
function _optimalSwapFromPrincipal(uint256 principalTokenAmount, address pool, address principalToken, address otherToken, int24 tickLower, int24 tickUpper, bytes swapData) internal returns (uint256 amount0, uint256 amount1)
```

Swaps the principal token to the other token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| principalTokenAmount | uint256 | The principal token |
| pool | address | The pool to swap |
| principalToken | address | The principal token |
| otherToken | address | The other token |
| tickLower | int24 | The lower tick of the position |
| tickUpper | int24 | The upper tick of the position |
| swapData | bytes | The swap data |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The result amount of pool's token0 |
| amount1 | uint256 | The result amount of pool's token1 |

### _swapToPrinciple

```solidity
function _swapToPrinciple(address pool, address principalToken, address token, uint256 amount, uint256 amountOutMin, bytes swapData) internal returns (uint256 amountOut, uint256 amountInUsed)
```

### getUnderlyingAssets

```solidity
function getUnderlyingAssets(struct AssetLib.Asset asset) external view returns (struct AssetLib.Asset[] underlyingAssets)
```

Gets the underlying assets of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to get the underlying assets |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| underlyingAssets | struct AssetLib.Asset[] | The underlying assets of the position |

### _getPoolForPosition

```solidity
function _getPoolForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (contract IUniswapV3Pool pool)
```

_Gets the pool for the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| tokenId | uint256 | The token id of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | contract IUniswapV3Pool | The pool for the position |

### _getAmountsForPosition

```solidity
function _getAmountsForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (uint256 amount0, uint256 amount1)
```

_Gets the amounts for the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| tokenId | uint256 | The token id of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The amount of token0 |
| amount1 | uint256 | The amount of token1 |

### _getAmountsForPool

```solidity
function _getAmountsForPool(contract IUniswapV3Pool pool) internal view returns (uint256 amount0, uint256 amount1)
```

_Gets the amounts for the pool_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | contract IUniswapV3Pool | IUniswapV3Pool |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The amount of token0 |
| amount1 | uint256 | The amount of token1 |

### _getFeesForPosition

```solidity
function _getFeesForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (uint256 fee0, uint256 fee1)
```

_Gets the fees for the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| tokenId | uint256 | The token id of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| fee0 | uint256 | The fee of token0 |
| fee1 | uint256 | The fee of token1 |

### _getFeeGrowthInside

```solidity
function _getFeeGrowthInside(contract IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, int24 tickCurrent) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
```

_Gets the fee growth inside the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | contract IUniswapV3Pool | The pool for the position |
| tickLower | int24 | The lower tick of the position |
| tickUpper | int24 | The upper tick of the position |
| tickCurrent | int24 | The current tick of the pool |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| feeGrowthInside0X128 | uint256 | The fee growth of token0 |
| feeGrowthInside1X128 | uint256 | The fee growth of token1 |

### _validateConfig

```solidity
function _validateConfig(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) internal view
```

_Checks the principal amount in the pool_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| fee | uint24 | The fee of the pool |
| token0 | address | The token0 of the pool |
| token1 | address | The token1 of the pool |
| tickLower | int24 | The lower tick of the position |
| tickUpper | int24 | The upper tick of the position |
| config | struct ICommon.VaultConfig | The configuration of the strategy |

### _isPoolAllowed

```solidity
function _isPoolAllowed(struct ICommon.VaultConfig config, address pool) internal pure returns (bool)
```

### receive

```solidity
receive() external payable
```

