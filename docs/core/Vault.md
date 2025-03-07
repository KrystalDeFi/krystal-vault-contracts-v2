# Solidity API

## Vault

### ADMIN_ROLE_HASH

```solidity
bytes32 ADMIN_ROLE_HASH
```

### principalToken

```solidity
address principalToken
```

### currentAssets

```solidity
mapping(address => mapping(uint256 => struct ICommon.Asset)) currentAssets
```

### constructor

```solidity
constructor() public
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _vaultAutomator, struct ICommon.Asset wrapAsset) public
```

Initializes the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |
| _owner | address | Owner of the vault |
| _vaultAutomator | address | Address of the vault automator |
| wrapAsset | struct ICommon.Asset | wrap asset |

### deposit

```solidity
function deposit(uint256 amount) external returns (uint256 shares)
```

Deposits the asset to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |

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

Allocates the assets to the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputAssets | struct ICommon.Asset[] | Input assets to allocate |
| strategy | contract IStrategy | Strategy to allocate to |
| data | bytes | Data for the strategy |

### deallocate

```solidity
function deallocate(contract IStrategy strategy, uint256 allocationAmount) external
```

Deallocates the assets from the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategy | contract IStrategy | Strategy to deallocate from |
| allocationAmount | uint256 | Amount to deallocate |

### getTotalValue

```solidity
function getTotalValue() external returns (uint256)
```

Returns the total value of the vault

### getAssetAllocations

```solidity
function getAssetAllocations() external returns (struct ICommon.Asset[] assets, uint256[] values)
```

Returns the asset allocations of the vault

