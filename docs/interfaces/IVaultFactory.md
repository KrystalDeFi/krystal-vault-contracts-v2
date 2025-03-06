# Solidity API

## IVaultFactory

### VaultCreated

```solidity
event VaultCreated()
```

### InvalidOwnerFee

```solidity
error InvalidOwnerFee()
```

### createVault

```solidity
function createVault(struct ICommon.VaultCreateParams params) external payable returns (address vault)
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

