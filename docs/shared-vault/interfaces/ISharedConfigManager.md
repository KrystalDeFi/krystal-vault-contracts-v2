# Solidity API

## ISharedConfigManager

### FeeRecipientUpdated

```solidity
event FeeRecipientUpdated(address previousRecipient, address newRecipient)
```

### WhitelistTargetsUpdated

```solidity
event WhitelistTargetsUpdated(address[] targets, bool isWhitelisted)
```

### WhitelistCallersUpdated

```solidity
event WhitelistCallersUpdated(address[] callers, bool isWhitelisted)
```

### WhitelistNfpmsUpdated

```solidity
event WhitelistNfpmsUpdated(address[] nfpms, bool isWhitelisted)
```

### WhitelistSwapRoutersUpdated

```solidity
event WhitelistSwapRoutersUpdated(address[] swapRouters, bool isWhitelisted)
```

### VaultPausedUpdated

```solidity
event VaultPausedUpdated(bool isVaultPaused)
```

### MaxPositionsUpdated

```solidity
event MaxPositionsUpdated(uint16 maxPositions)
```

### isVaultPaused

```solidity
function isVaultPaused() external view returns (bool)
```

### feeRecipient

```solidity
function feeRecipient() external view returns (address)
```

### platformFeeBasisPoint

```solidity
function platformFeeBasisPoint() external view returns (uint16)
```

Platform fee on LP performance collections (basis points), sent to `feeRecipient` via `LpFeeTaker` on exit.

### setPlatformFeeBasisPoint

```solidity
function setPlatformFeeBasisPoint(uint16 basisPoints) external
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

### isWhitelistedNfpm

```solidity
function isWhitelistedNfpm(address nfpm) external view returns (bool)
```

### setWhitelistNfpms

```solidity
function setWhitelistNfpms(address[] nfpms, bool isWhitelisted) external
```

### isWhitelistedSwapRouter

```solidity
function isWhitelistedSwapRouter(address swapRouter) external view returns (bool)
```

### setWhitelistSwapRouters

```solidity
function setWhitelistSwapRouters(address[] swapRouters, bool isWhitelisted) external
```

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

### setFeeRecipient

```solidity
function setFeeRecipient(address newFeeRecipient) external
```

### maxPositions

```solidity
function maxPositions() external view returns (uint16)
```

Maximum number of LP positions a vault may hold simultaneously.
        Limits the per-deposit and per-withdraw loop cost. Default: 20.

### setMaxPositions

```solidity
function setMaxPositions(uint16 _maxPositions) external
```

