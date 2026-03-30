# Solidity API

## ISharedVaultFactory

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
function createVault(string name, string symbol, address[4] tokens, uint256[4] initialAmounts) external returns (address vault)
```

### createVault

```solidity
function createVault(string name, string symbol, address[4] tokens, uint256[4] initialAmounts, address[] strategies, bytes[] strategiesData, uint256[] ethValues) external payable returns (address vault)
```

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

