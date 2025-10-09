# Solidity API

## LpChainingStrategy

### configManager

```solidity
contract IConfigManager configManager
```

### constructor

```solidity
constructor(address _configManager) public
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
| principalToken | address | The principal token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valueInPrincipal | uint256 | The value of the asset in terms of principalToken |

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig, bytes data) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Converts the asset to another assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to convert |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |
| data | bytes | The data for the instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _batch

```solidity
function _batch(struct AssetLib.Asset[] assets, struct ILpChainingStrategy.ChainingInstruction[] instructions, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _decreaseAndBatch

```solidity
function _decreaseAndBatch(struct AssetLib.Asset[] assets, struct ILpChainingStrategy.ChainingInstruction[] instructions, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut, uint256 amountTokenOutMin, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[])
```

Harvest the asset fee

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to harvest |
| tokenOut | address | The token to swap to |
| amountTokenOutMin | uint256 | The minimum amount out by tokenOut |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | returnAssets The assets that were returned to the msg.sender |

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig vaultConfig) external payable returns (struct AssetLib.Asset[])
```

convert the asset from the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert |
| principalTokenAmount | uint256 | The amount of principal token |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | returnAssets The assets that were returned to the msg.sender |

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

convert the asset to the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert |
| shares | uint256 | The shares to convert |
| totalSupply | uint256 | The total supply of the shares |
| config | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external view
```

Revalidate the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to revalidate |
| config | struct ICommon.VaultConfig | The vault configuration |

### _delegateCallToLpStrategy

```solidity
function _delegateCallToLpStrategy(address strategy, bytes cData) internal returns (bytes returnData)
```

### _isIncludedDecrease

```solidity
function _isIncludedDecrease(struct ILpChainingStrategy.ChainingInstruction[] instructions) internal pure returns (bool)
```

### receive

```solidity
receive() external payable
```

Fallback function to receive Ether. This is required for the contract to accept ETH transfers.

