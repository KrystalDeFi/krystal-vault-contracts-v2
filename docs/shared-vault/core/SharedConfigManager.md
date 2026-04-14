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

### whitelistedNfpms

```solidity
mapping(address => bool) whitelistedNfpms
```

### whitelistedSwapRouters

```solidity
mapping(address => bool) whitelistedSwapRouters
```

### isVaultPaused

```solidity
bool isVaultPaused
```

### feeRecipient

```solidity
address feeRecipient
```

### platformFeeBasisPoint

```solidity
uint16 platformFeeBasisPoint
```

Platform fee on LP performance collections (basis points), sent to `feeRecipient` via `LpFeeTaker` on exit.

### initialize

```solidity
function initialize(address _owner, address[] _whitelistTargets, address[] _whitelistCallers, address _feeRecipient, address[] _whitelistNfpms, address[] _whitelistSwapRouters) public
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

### setWhitelistNfpms

```solidity
function setWhitelistNfpms(address[] nfpms, bool _isWhitelisted) external
```

### isWhitelistedNfpm

```solidity
function isWhitelistedNfpm(address nfpm) external view returns (bool)
```

### setWhitelistSwapRouters

```solidity
function setWhitelistSwapRouters(address[] swapRouters, bool _isWhitelisted) external
```

### isWhitelistedSwapRouter

```solidity
function isWhitelistedSwapRouter(address swapRouter) external view returns (bool)
```

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

### setFeeRecipient

```solidity
function setFeeRecipient(address newFeeRecipient) external
```

### setPlatformFeeBasisPoint

```solidity
function setPlatformFeeBasisPoint(uint16 basisPoints) external
```

