# Solidity API

## Vault

### SHARES_PRECISION

```solidity
uint256 SHARES_PRECISION
```

### ADMIN_ROLE_HASH

```solidity
bytes32 ADMIN_ROLE_HASH
```

### configManager

```solidity
contract IConfigManager configManager
```

### vaultOwner

```solidity
address vaultOwner
```

### vaultConfig

```solidity
struct ICommon.VaultConfig vaultConfig
```

### onlyAdminOrAutomator

```solidity
modifier onlyAdminOrAutomator()
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _configManager) public
```

Initializes the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |
| _owner | address | Owner of the vault |
| _configManager | address | Address of the whitelist manager |

### deposit

```solidity
function deposit(uint256 principalAmount) external returns (uint256 shares)
```

Deposits the asset to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| principalAmount | uint256 | Amount of in principalToken |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares minted |

### withdraw

```solidity
function withdraw(uint256 shares) external
```

Withdraws the asset from the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares to be burned |

### allocate

```solidity
function allocate(struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, bytes data) external
```

Allocates un-used assets to the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputAssets | struct AssetLib.Asset[] | Input assets to allocate |
| strategy | contract IStrategy | Strategy to allocate to |
| data | bytes | Data for the strategy |

### deallocate

```solidity
function deallocate(address token, uint256 tokenId, uint256 amount, bytes data) external
```

Deallocates the assets from the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | asset's token address |
| tokenId | uint256 | asset's token ID |
| amount | uint256 | Amount to deallocate |
| data | bytes | Data for strategy execution |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset) external
```

### _harvest

```solidity
function _harvest(struct AssetLib.Asset asset) internal
```

### getTotalValue

```solidity
function getTotalValue() public returns (uint256 totalValue)
```

Returns the total value of the vault

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| totalValue | uint256 | Total value of the vault in principal token |

### getAssetAllocations

```solidity
function getAssetAllocations() external returns (struct AssetLib.Asset[] assets)
```

Returns the asset allocations of the vault

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | Asset allocations of the vault |

### sweepToken

```solidity
function sweepToken(address[] tokens) external
```

Sweeps the tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |

### sweepNFTToken

```solidity
function sweepNFTToken(address[] _tokens, uint256[] _tokenIds) external
```

Sweeps the non-fungible tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _tokens | address[] | Tokens to sweep |
| _tokenIds | uint256[] | Token IDs to sweep |

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

grant admin role to the address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _address | address | The address to which the admin role is granted |

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

revoke admin role from the address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _address | address | The address from which the admin role is revoked |

### setVaultConfig

```solidity
function setVaultConfig(struct ICommon.VaultConfig _config) external
```

Sets the vault config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _config | struct ICommon.VaultConfig | New vault config |

### _addAssets

```solidity
function _addAssets(struct AssetLib.Asset[] newAssets) internal
```

_Adds multiple assets to the vault_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newAssets | struct AssetLib.Asset[] | New assets to add |

### _transferAssets

```solidity
function _transferAssets(struct AssetLib.Asset[] assets, address to) internal
```

### _transferAsset

```solidity
function _transferAsset(struct AssetLib.Asset asset, address to) internal
```

_Transfers the asset to the recipient_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | AssetLib.Asset to transfer |
| to | address | Recipient of the asset |

### getInventory

```solidity
function getInventory() external view returns (struct AssetLib.Asset[] assets)
```

