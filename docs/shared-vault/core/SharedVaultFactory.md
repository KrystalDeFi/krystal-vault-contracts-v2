# Solidity API

## SharedVaultFactory

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
function initialize(address _owner, address _configManager, address _vaultImplementation) external
```

### createVault

```solidity
function createVault(string name, string symbol, address[4] tokens, uint256[4] initialAmounts) external returns (address vault)
```

Create a shared vault with initial token deposits

### createVault

```solidity
function createVault(string name, string symbol, address[4] tokens, uint256[4] initialAmounts, address strategy, bytes strategyData) external payable returns (address vault)
```

Create a shared vault with initial deposits and execute a strategy

### _createVault

```solidity
function _createVault(string name, string symbol, address[4] tokens, uint256[4] initialAmounts) internal returns (address vault)
```

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

Check if a vault was created by this factory

### getVaultsByAddress

```solidity
function getVaultsByAddress(address owner) external view returns (address[])
```

Get all vaults created by an address

### allVaultsLength

```solidity
function allVaultsLength() external view returns (uint256)
```

Get total number of vaults

### pause

```solidity
function pause() external
```

### unpause

```solidity
function unpause() external
```

### setConfigManager

```solidity
function setConfigManager(address _configManager) external
```

### setVaultImplementation

```solidity
function setVaultImplementation(address _vaultImplementation) external
```

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view
```

Check if the caller has permission to withdraw

_Must be implemented by the child contract_

