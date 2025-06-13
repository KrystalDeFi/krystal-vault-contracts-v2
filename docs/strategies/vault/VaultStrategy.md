# Solidity API

## VaultStrategy

### vaultFactory

```solidity
contract IVaultFactory vaultFactory
```

### constructor

```solidity
constructor(address _vaultFactory) public
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset, address) external view returns (uint256)
```

Get value of the asset in terms of principalToken

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to get the value |
|  | address |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | valueInPrincipal The value of the asset in terms of principalToken |

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig, bytes data) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Converts the asset to another assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to convert |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
|  | struct ICommon.FeeConfig |  |
| data | bytes | The data for the instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _deposit

```solidity
function _deposit(struct AssetLib.Asset[] assets, struct IVaultStrategy.DepositParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Deposit assets into the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to deposit |
| params | struct IVaultStrategy.DepositParams | The deposit parameters |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _withdraw

```solidity
function _withdraw(struct AssetLib.Asset[] assets, struct IVaultStrategy.WithdrawParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Withdraw assets from the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to withdraw |
| params | struct IVaultStrategy.WithdrawParams | The withdraw parameters |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address, uint256 amountTokenOutMin, struct ICommon.VaultConfig, struct ICommon.FeeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Harvest the asset fee

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to harvest |
|  | address |  |
| amountTokenOutMin | uint256 | The minimum amount out by tokenOut |
|  | struct ICommon.VaultConfig |  |
|  | struct ICommon.FeeConfig |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig vaultConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
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
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256, struct ICommon.VaultConfig config, struct ICommon.FeeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

convert the asset to the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert |
| shares | uint256 | The shares to convert |
|  | uint256 |  |
| config | struct ICommon.VaultConfig | The vault configuration |
|  | struct ICommon.FeeConfig |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external
```

Revalidate the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to revalidate |
| config | struct ICommon.VaultConfig | The vault configuration |

### receive

```solidity
receive() external payable
```

Fallback function to receive Ether. This is required for the contract to accept ETH transfers.

