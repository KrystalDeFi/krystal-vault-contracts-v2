# Solidity API

## ISharedConfigManager

### FeeRecipientUpdated

```solidity
event FeeRecipientUpdated(address previousRecipient, address newRecipient)
```

### isVaultPaused

```solidity
function isVaultPaused() external view returns (bool)
```

### feeRecipient

```solidity
function feeRecipient() external view returns (address)
```

### isWhitelistedStrategy

```solidity
function isWhitelistedStrategy(address strategy) external view returns (bool)
```

### setWhitelistStrategies

```solidity
function setWhitelistStrategies(address[] strategies, bool isWhitelisted) external
```

### isWhitelistedTarget

```solidity
function isWhitelistedTarget(address target) external view returns (bool)
```

### setWhitelistTargets

```solidity
function setWhitelistTargets(address[] targets, bool isWhitelisted) external
```

### isWhitelistedCaller

```solidity
function isWhitelistedCaller(address caller) external view returns (bool)
```

### setWhitelistCallers

```solidity
function setWhitelistCallers(address[] callers, bool isWhitelisted) external
```

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

### setFeeRecipient

```solidity
function setFeeRecipient(address newFeeRecipient) external
```

