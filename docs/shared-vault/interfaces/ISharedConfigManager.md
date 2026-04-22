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

### MinTokenPrecisionUpdated

```solidity
event MinTokenPrecisionUpdated(uint8 precision)
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

### minTokenPrecision

```solidity
function minTokenPrecision() external view returns (uint8)
```

Decimal-place precision that defines the protocol-wide dust floor.
        The effective minimum amount for any token is:

            minAmt = 10 ** max(0, token.decimals() - minTokenPrecision)

        Examples with the default precision of 5 (= 0.00001 of any token):
          USDC  (6 dec)  → 10 ** (6-5)  = 10        ≈ 0.00001 USDC
          WBTC  (8 dec)  → 10 ** (8-5)  = 1 000     ≈ 0.00001 BTC  (1000 sats)
          WETH  (18 dec) → 10 ** (18-5) = 10 000 000 000 000  ≈ 0.00001 ETH

        This approach makes the floor token-agnostic: one configured value scales
        correctly for every token regardless of its decimal precision.

        Protects against two dust-related issues:
        1. DEPOSIT DILUTION ATTACK — floor-division rounds a depositor's tiny proportional
           slice to zero, letting them receive shares without contributing to every asset.
           SharedVault rounds slices UP (ceiling) and then raises to the computed min,
           so the depositor always over-pays for sub-threshold slices.
        2. GATEWAY SWAP FAILURES — swap aggregators reject micro amounts. The floor ensures
           every proportional slice is large enough for an aggregator to process.

        A value of 0 disables the floor (only ceiling rounding remains active).

### setMinTokenPrecision

```solidity
function setMinTokenPrecision(uint8 precision) external
```

Set the dust-floor precision level.
        5 → 0.00001 of any token (default).
        0 → floor disabled (ceiling rounding still prevents the dilution attack).

