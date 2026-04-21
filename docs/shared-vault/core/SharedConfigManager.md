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

### maxPositions

```solidity
uint16 maxPositions
```

Maximum number of LP positions a vault may hold simultaneously.
        Limits the per-deposit and per-withdraw loop cost. Default: 20.

### minTokenAmount

```solidity
uint256 minTokenAmount
```

Global minimum "swappable" amount enforced uniformly on every vault token during
        proportional deposit/withdraw computations. A single protocol-wide value is used
        rather than a per-token mapping because the config owner does not control which
        tokens any given vault is created with. Protects against two dust-related issues:

        1. DEPOSIT DILUTION ATTACK — without a minimum, when a vault holds tiny balances of
           some token (e.g. 50 wei of USDT alongside 100e18 of another token), floor-division
           rounds the depositor's proportional slice of that dust token down to zero. The
           depositor then receives shares without paying for the dust token — dilution over
           many small deposits. SharedVault rounds the proportional slice UP and then raises
           it to `minTokenAmount` on deposit, so the depositor always overpays for sub-min
           slices (existing holders protected).

        2. GATEWAY SWAP FAILURES — swap aggregators cannot produce/consume micro amounts
           (e.g. 1 wei of USDT). SharedVaultGateway therefore cannot fulfill proportional
           deposits or swap back proportional withdrawals when a slice is sub-threshold.
           Setting a modest floor (e.g. 10 base units) ensures the gateway always sees
           swappable amounts, regardless of the underlying token's decimals.

        Unit: raw base units (wei-like). A value of 0 disables the minimum entirely and
        restores the legacy floor-division behaviour.

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

### setMaxPositions

```solidity
function setMaxPositions(uint16 _maxPositions) external
```

### setMinTokenAmount

```solidity
function setMinTokenAmount(uint256 _minTokenAmount) external
```

Set the global minimum token amount. Pass 0 to disable the minimum.

