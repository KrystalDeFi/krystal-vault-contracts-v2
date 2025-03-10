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

### whitelistManager

```solidity
contract IWhitelistManager whitelistManager
```

### principalToken

```solidity
address principalToken
```

### currentAssets

```solidity
mapping(address => mapping(uint256 => struct ICommon.Asset)) currentAssets
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _whitelistManager, address _vaultAutomator) public
```

Initializes the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |
| _owner | address | Owner of the vault |
| _whitelistManager | address |  |
| _vaultAutomator | address | Address of the vault automator |

### deposit

```solidity
function deposit(uint256 shares) external returns (uint256 returnShares)
```

Deposits the asset to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares to be minted |

### depositPrinciple

```solidity
function depositPrinciple(uint256 amount) external returns (uint256 shares)
```

Deposits the principal to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |

### allocate

```solidity
function allocate(struct ICommon.Asset[] inputAssets, contract IStrategy strategy, bytes data) external
```

Allocates un-used assets to the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputAssets | struct ICommon.Asset[] | Input assets to allocate |
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

### _addAssets

```solidity
function _addAssets(struct ICommon.Asset[] newAssets) internal
```

### _addAsset

```solidity
function _addAsset(struct ICommon.Asset asset) internal
```

### _transferAsset

```solidity
function _transferAsset(struct ICommon.Asset asset, address to) internal
```

### getTotalValue

```solidity
function getTotalValue() external returns (uint256 value)
```

Returns the total value of the vault

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| value | uint256 | Total value of the vault in principal token |

### getAssetAllocations

```solidity
function getAssetAllocations() external returns (struct ICommon.Asset[] assets, uint256[] values)
```

Returns the asset allocations of the vault

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct ICommon.Asset[] | Asset allocations of the vault |
| values | uint256[] | Asset values of the vault |

### sweepToken

```solidity
function sweepToken(address[] tokens) external
```

Sweeps the tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |

### sweepNFToken

```solidity
function sweepNFToken(address[] tokens, uint256[] tokenIds) external
```

Sweeps the non-fungible tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |
| tokenIds | uint256[] | Token IDs to sweep |

