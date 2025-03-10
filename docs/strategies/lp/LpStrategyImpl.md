# Solidity API

## LpStrategyImpl

### principalToken

```solidity
address principalToken
```

### constructor

```solidity
constructor() public
```

### initialize

```solidity
function initialize(address _principalToken) public
```

Initializes the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _principalToken | address | The principal token of the strategy |

### valueOf

```solidity
function valueOf(struct ICommon.Asset asset) external view returns (uint256 value)
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

### convertIntoExisting

```solidity
function convertIntoExisting(struct ICommon.Asset existingAsset, struct ICommon.Asset[] newAssets, bytes data) external returns (struct ICommon.Asset[] returnAssets)
```

Converts the asset to another assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct ICommon.Asset | The existing asset to convert |
| newAssets | struct ICommon.Asset[] | The new assets to convert |
| data | bytes | The data for the instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct ICommon.Asset[] | The assets that were returned to the msg.sender |

### _mintPosition

```solidity
function _mintPosition(struct ICommon.Asset[] assets, struct ILpStrategy.MintPositionParams params) internal returns (struct ICommon.Asset[] returnAssets)
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

### _increaseLiquidity

```solidity
function _increaseLiquidity(struct ICommon.Asset[] assets, struct ILpStrategy.IncreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
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

### _decreaseLiquidity

```solidity
function _decreaseLiquidity(struct ICommon.Asset[] assets, struct ILpStrategy.DecreaseLiquidityParams params) internal returns (struct ICommon.Asset[] returnAssets)
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

### getUnderlyingAssets

```solidity
function getUnderlyingAssets(struct ICommon.Asset asset) external view returns (struct ICommon.Asset[] underlyingAssets)
```

### _getPoolForPosition

```solidity
function _getPoolForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (contract IUniswapV3Pool pool)
```

### _getAmountsForPosition

```solidity
function _getAmountsForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (uint256 amount0, uint256 amount1)
```

### _getFeesForPosition

```solidity
function _getFeesForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (uint256 fee0, uint256 fee1)
```

### _getFeeGrowthInside

```solidity
function _getFeeGrowthInside(contract IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, int24 tickCurrent) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
```

### receive

```solidity
receive() external payable
```

