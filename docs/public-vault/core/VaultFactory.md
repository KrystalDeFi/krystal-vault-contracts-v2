# Solidity API

## VaultFactory

### WETH

```solidity
address WETH
```

### configManager

```solidity
address configManager
```

### vaultImplementation

```solidity
address vaultImplementation
```

### vaultsByAddress

```solidity
mapping(address => address[]) vaultsByAddress
```

### allVaults

```solidity
address[] allVaults
```

### isVaultAddress

```solidity
mapping(address => bool) isVaultAddress
```

### initialize

```solidity
function initialize(address _owner, address _weth, address _configManager, address _vaultImplementation) external
```

### createVault

```solidity
function createVault(struct ICommon.VaultCreateParams params) external payable returns (address vault)
```

Create a new vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | address | Address of the new vault |

### createVaultAndAllocate

```solidity
function createVaultAndAllocate(struct ICommon.VaultCreateParams params, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, bytes data) external payable returns (address vault)
```

Create a new vault and allocate

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |
| inputAssets | struct AssetLib.Asset[] | Assets to allocate |
| strategy | contract IStrategy | Strategy to use for allocation |
| data | bytes | Additional data for allocation |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | address | Address of the new vault |

### _createVault

```solidity
function _createVault(struct ICommon.VaultCreateParams params) internal returns (address vault)
```

### pause

```solidity
function pause() external
```

Pause the contract

### unpause

```solidity
function unpause() external
```

Unpause the contract

### setConfigManager

```solidity
function setConfigManager(address _configManager) external
```

Set the ConfigManager address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _configManager | address | Address of the new ConfigManager |

### setVaultImplementation

```solidity
function setVaultImplementation(address _vaultImplementation) external
```

Set the Vault implementation

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vaultImplementation | address | Address of the new vault implementation |

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

Check if a vault created by this factory

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | address | Address of the vault to check |

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view
```

Check if the caller has permission to withdraw

_Must be implemented by the child contract_

