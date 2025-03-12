# Solidity API

## IVaultFactory

### VaultCreated

```solidity
event VaultCreated(address owner, address vault, struct ICommon.VaultCreateParams params)
```

### WhitelistManagerSet

```solidity
event WhitelistManagerSet(address whitelistManager)
```

### VaultImplementationSet

```solidity
event VaultImplementationSet(address vaultImplementation)
```

### VaultAutomatorSet

```solidity
event VaultAutomatorSet(address vaultAutomator)
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

### setWhitelistManager

```solidity
function setWhitelistManager(address _whitelistManager) external
```

### setVaultImplementation

```solidity
function setVaultImplementation(address _vaultImplementation) external
```

### setVaultAutomator

```solidity
function setVaultAutomator(address _vaultAutomator) external
```

### setPlatformFeeRecipient

```solidity
function setPlatformFeeRecipient(address _platformFeeRecipient) external
```

### setPlatformFeeBasisPoint

```solidity
function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) external
```
