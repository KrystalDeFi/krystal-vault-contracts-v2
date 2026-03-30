# Solidity API

## SharedConfigManager

### whitelistedTargets

```solidity
mapping(address => bool) whitelistedTargets
```

### whitelistedCallers

```solidity
mapping(address => bool) whitelistedCallers
```

### isVaultPaused

```solidity
bool isVaultPaused
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
function setWhitelistTargets(address[] targets, bool _isWhitelisted) external
```

### isWhitelistedTarget

```solidity
function isWhitelistedTarget(address target) external view returns (bool)
```

### setWhitelistCallers

```solidity
function setWhitelistCallers(address[] callers, bool _isWhitelisted) external
```

### isWhitelistedCaller

```solidity
function isWhitelistedCaller(address caller) external view returns (bool)
```

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

### setFeeRecipient

```solidity
function setFeeRecipient(address newFeeRecipient) external
```

