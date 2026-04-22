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

### minTokenPrecision

```solidity
uint8 minTokenPrecision
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

### initialize

```solidity
function initialize(address _owner, address[] _whitelistTargets, address[] _whitelistCallers, address _feeRecipient, uint16 _platformFeeBasisPoint, address[] _whitelistNfpms, address[] _whitelistSwapRouters) public
```

One-time initializer. Argument order is intentional; pass-by-position callers must
        match this exact sequence to avoid silently misrouting values:
        1. _owner                  — OwnableUpgradeable owner
        2. _whitelistTargets       — strategy addresses to whitelist as delegatecall targets
        3. _whitelistCallers       — addresses authorized as whitelisted callers
        4. _feeRecipient           — address that receives platform fees
        5. _platformFeeBasisPoint  — platform fee in basis points (≤ 10 000)
        6. _whitelistNfpms         — NFT position managers to whitelist
        7. _whitelistSwapRouters   — swap routers/aggregators to whitelist

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

### setMinTokenPrecision

```solidity
function setMinTokenPrecision(uint8 precision) external
```

Set the dust-floor precision level.
        5 → 0.00001 of any token (default).
        0 → floor disabled (ceiling rounding still prevents the dilution attack).

