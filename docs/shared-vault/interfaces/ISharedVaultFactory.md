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
function createVault(string name, address[4] tokens, uint256[4] initialAmounts) external payable returns (address vault)
```

Create a shared vault with initial token deposits.

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts, address[] targets, uint256[] callValues, bytes[] data) external payable returns (address vault)
```

Create a shared vault with initial deposits and execute multiple strategy actions.

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

