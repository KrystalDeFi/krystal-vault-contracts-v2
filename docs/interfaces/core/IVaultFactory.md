# Solidity API

## IVaultFactory

### VaultCreated

```solidity
event VaultCreated(address owner, address vault, struct ICommon.VaultCreateParams params)
```

### ConfigManagerSet

```solidity
event ConfigManagerSet(address configManager)
```

### VaultImplementationSet

```solidity
event VaultImplementationSet(address vaultImplementation)
```

### InvalidPrincipalToken

```solidity
error InvalidPrincipalToken()
```

### createVault

```solidity
function createVault(struct ICommon.VaultCreateParams params) external payable returns (address vault)
```

### setConfigManager

```solidity
function setConfigManager(address _configManager) external
```

### setVaultImplementation

```solidity
function setVaultImplementation(address _vaultImplementation) external
```

### WETH

```solidity
function WETH() external view returns (address)
```

