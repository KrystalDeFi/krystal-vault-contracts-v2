# Solidity API

## IPrivateVaultFactory

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
function createVault(string name) external payable returns (address vault)
```

### createVault

```solidity
function createVault(string name, address[] tokens, uint256[] amounts, address[] nfts721, uint256[] nfts721TokenIds, address[] nfts1155, uint256[] nfts1155TokenIds, uint256[] nfts1155Amounts, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes) external payable returns (address vault)
```

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

