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

### PlatformFeeRecipientSet

```solidity
event PlatformFeeRecipientSet(address platformFeeRecipient)
```

### PlatformFeeBasisPointSet

```solidity
event PlatformFeeBasisPointSet(uint16 platformFeeBasisPoint)
```

### InvalidOwnerFee

```solidity
error InvalidOwnerFee()
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

### setPlatformFeeRecipient

```solidity
function setPlatformFeeRecipient(address _platformFeeRecipient) external
```

### setPlatformFeeBasisPoint

```solidity
function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) external
```

