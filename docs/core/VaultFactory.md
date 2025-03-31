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

### constructor

```solidity
constructor(address _owner, address _weth, address _configManager, address _vaultImplementation) public
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

