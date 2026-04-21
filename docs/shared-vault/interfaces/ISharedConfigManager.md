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

### MinTokenAmountUpdated

```solidity
event MinTokenAmountUpdated(uint256 minTokenAmount)
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

### minTokenAmount

```solidity
function minTokenAmount() external view returns (uint256)
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

### setMinTokenAmount

```solidity
function setMinTokenAmount(uint256 _minTokenAmount) external
```

Set the global minimum token amount. Pass 0 to disable the minimum.

