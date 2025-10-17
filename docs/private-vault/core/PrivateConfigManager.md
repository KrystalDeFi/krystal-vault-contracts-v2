# Solidity API

## PrivateConfigManager

### whitelistTargets

```solidity
mapping(address => bool) whitelistTargets
```

### whitelistCallers

```solidity
mapping(address => bool) whitelistCallers
```

### isVaultPaused

```solidity
bool isVaultPaused
```

### enforceTargetWhitelistForOwners

```solidity
bool enforceTargetWhitelistForOwners
```

### feeRecipient

```solidity
address feeRecipient
```

### initialize

```solidity
function initialize(address _owner, address[] _whitelistTargets, address[] _whitelistCallers, address _feeRecipient) public
```

### setWhitelistTargets

```solidity
function setWhitelistTargets(address[] targets, bool isWhitelisted) external
```

### isWhitelistedTarget

```solidity
function isWhitelistedTarget(address target) external view returns (bool)
```

### setWhitelistCallers

```solidity
function setWhitelistCallers(address[] callers, bool isWhitelisted) external
```

### isWhitelistedCaller

```solidity
function isWhitelistedCaller(address caller) external view returns (bool)
```

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

### setEnforceTargetWhitelistForOwners

```solidity
function setEnforceTargetWhitelistForOwners(bool _enforceTargetWhitelistForOwners) external
```

### setFeeRecipient

```solidity
function setFeeRecipient(address newFeeRecipient) external
```

