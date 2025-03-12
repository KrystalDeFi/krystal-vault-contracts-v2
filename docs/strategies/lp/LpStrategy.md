# Solidity API

## LpStrategy

### principleToken

```solidity
address principleToken
```

### optimalSwapper

```solidity
contract IOptimalSwapper optimalSwapper
```

### constructor

```solidity
constructor(address _principleToken, address _optimalSwapper) public
```

### valueOf

```solidity
function valueOf(struct ICommon.Asset asset) external view returns (struct ICommon.Asset[] assets)
```

Deposits the asset to the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct ICommon.Asset | The asset to be calculated |

### convert

```solidity
function convert(struct ICommon.Asset[] assets, bytes data) external returns (struct ICommon.Asset[] returnAssets)
```

Converts the asset to another assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct ICommon.Asset[] | The assets to convert |
| data | bytes | The data for the instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct ICommon.Asset[] | The assets that were returned to the msg.sender |

### harvest

```solidity
function harvest(struct ICommon.Asset asset) external returns (struct ICommon.Asset[] returnAssets)
```

### convertIntoExisting

```solidity
function convertIntoExisting(struct ICommon.Asset existingAsset, struct ICommon.Asset[] assets) external returns (struct ICommon.Asset[] returnAssets)
```

### mintPosition

```solidity
function mintPosition(struct ICommon.Asset[] assets, struct ILpStrategy.MintPositionParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

Mints a new position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct ICommon.Asset[] | The assets to mint the position, assets[0] = token0, assets[1] = token1 |
| params | struct ILpStrategy.MintPositionParams | The parameters for minting the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct ICommon.Asset[] | The assets that were returned to the msg.sender |

### swapAndMintPosition

```solidity
function swapAndMintPosition(struct ICommon.Asset[] assets, struct ILpStrategy.SwapAndMintPositionParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

### _mintPosition

```solidity
function _mintPosition(struct ICommon.Asset[] assets, struct ILpStrategy.MintPositionParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

### increaseLiquidity

```solidity
function increaseLiquidity(struct ICommon.Asset[] assets, struct ILpStrategy.IncreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

Increases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct ICommon.Asset[] | The assets to increase the liquidity assets[2] = lpAsset |
| params | struct ILpStrategy.IncreaseLiquidityParams | The parameters for increasing the liquidity |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct ICommon.Asset[] | The assets that were returned to the msg.sender |

### swapAndIncreaseLiquidity

```solidity
function swapAndIncreaseLiquidity(struct ICommon.Asset[] assets, struct ILpStrategy.SwapAndIncreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

### _increaseLiquidity

```solidity
function _increaseLiquidity(struct ICommon.Asset[] assets, struct ILpStrategy.IncreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

### decreaseLiquidity

```solidity
function decreaseLiquidity(struct ICommon.Asset[] assets, struct ILpStrategy.DecreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

Decreases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct ICommon.Asset[] | The assets to decrease the liquidity assets[0] = lpAsset |
| params | struct ILpStrategy.DecreaseLiquidityParams | The parameters for decreasing the liquidity |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct ICommon.Asset[] | The assets that were returned to the msg.sender |

### decreaseLiquidityAndSwap

```solidity
function decreaseLiquidityAndSwap(struct ICommon.Asset[] assets, struct ILpStrategy.DecreaseLiquidityAndSwapParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

### _decreaseLiquidity

```solidity
function _decreaseLiquidity(struct ICommon.Asset lpAsset, struct ILpStrategy.DecreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
```

### _optimalSwapFromPrinciple

```solidity
function _optimalSwapFromPrinciple(uint256 amount, address pool, address token0, address token1, int24 tickLower, int24 tickUpper, bytes swapData) internal returns (uint256 amount0Result, uint256 amount1Result)
```

### getUnderlyingAssets

```solidity
function getUnderlyingAssets(struct ICommon.Asset asset) external view returns (struct ICommon.Asset[] underlyingAssets)
```

Gets the underlying assets of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct ICommon.Asset | The asset to get the underlying assets |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| underlyingAssets | struct ICommon.Asset[] | The underlying assets of the position |

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

### receive

```solidity
receive() external payable
```

