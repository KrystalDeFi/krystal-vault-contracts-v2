# Solidity API

## ISharedConfigManager

### FeeRecipientUpdated

```solidity
event FeeRecipientUpdated(address previousRecipient, address newRecipient)
```

### WhitelistStrategiesUpdated

```solidity
event WhitelistStrategiesUpdated(address[] strategies, bool isWhitelisted)
```

### WhitelistTargetsUpdated

```solidity
event WhitelistTargetsUpdated(address[] targets, bool isWhitelisted)
```

### WhitelistCallersUpdated

```solidity
event WhitelistCallersUpdated(address[] callers, bool isWhitelisted)
```

### VaultPausedUpdated

```solidity
event VaultPausedUpdated(bool isVaultPaused)
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

