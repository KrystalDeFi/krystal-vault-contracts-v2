# Solidity API

## SharedVaultFactory

### configManager

```solidity
contract ISharedConfigManager configManager
```

### vaultImplementation

```solidity
address vaultImplementation
```

### weth

```solidity
address weth
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
function initialize(address _owner, address _configManager, address _vaultImplementation, address _weth) external
```

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts) external payable returns (address vault)
```

Create a shared vault with initial token deposits

_Send ETH via msg.value to auto-wrap to WETH for the initial deposit_

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts, address[] strategies, bytes[] strategiesData, uint256[] ethValues) external payable returns (address vault)
```

Create a shared vault with initial deposits and execute multiple strategies

_Send ETH via msg.value to cover both the initial WETH deposit (if WETH is a vault
     token with a non-zero initialAmount) AND the strategy ETH values.
     msg.value must equal initialAmounts[wethSlot] + sum(ethValues).
     If WETH is not in the initial deposit, msg.value must equal sum(ethValues) exactly._

### _createVault

```solidity
function _createVault(string name, address[4] tokens, uint256[4] initialAmounts, uint256 ethForDeposit) internal returns (address vault)
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

