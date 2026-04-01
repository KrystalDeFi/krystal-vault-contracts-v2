# Solidity API

## ISharedVaultFactory

### DuplicateVaultName

```solidity
error DuplicateVaultName()
```

### VaultCreated

```solidity
event VaultCreated(address owner, address vault, string name)
```

### ConfigManagerSet

```solidity
event ConfigManagerSet(address configManager)
```

### VaultImplementationSet

```solidity
event VaultImplementationSet(address vaultImplementation)
```

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts, address _operator) external payable returns (address vault)
```

Create a shared vault with initial token deposits.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| name | string |  |
| tokens | address[4] |  |
| initialAmounts | uint256[4] |  |
| _operator | address | Initial vault operator (address(0) = no operator until set by owner). |

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts, address _operator, address[] strategies, bytes[] strategiesData, uint256[] ethValues) external payable returns (address vault)
```

Create a shared vault with initial deposits and execute multiple strategy actions.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| name | string |  |
| tokens | address[4] |  |
| initialAmounts | uint256[4] |  |
| _operator | address | Initial vault operator (address(0) = no operator until set by owner). |
| strategies | address[] |  |
| strategiesData | bytes[] |  |
| ethValues | uint256[] |  |

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

