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

### valueOf

```solidity
function valueOf(struct ICommon.Asset asset) external view returns (uint256 value)
```

Deposits the asset to the strategy

### convert

```solidity
function convert(struct ICommon.Asset[] assets, bytes data) external returns (struct ICommon.Asset[] returnAssets)
```

Converts the asset to another assets

### convertIntoExisting

```solidity
function convertIntoExisting(struct ICommon.Asset existingAsset, struct ICommon.Asset[] newAssets, bytes data) external returns (struct ICommon.Asset[] asset)
```

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

### receive

```solidity
receive() external payable
```

