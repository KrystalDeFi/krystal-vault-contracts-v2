# Solidity API

## IPrivateConfigManager

### isVaultPaused

```solidity
function isVaultPaused() external view returns (bool)
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

### enforceTargetWhitelistForOwners

```solidity
function enforceTargetWhitelistForOwners() external view returns (bool)
```

### setEnforceTargetWhitelistForOwners

```solidity
function setEnforceTargetWhitelistForOwners(bool _enforceTargetWhitelistForOwners) external
```

