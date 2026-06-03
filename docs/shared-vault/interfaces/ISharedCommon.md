# Solidity API

## ISharedCommon

### CallType

Call discipline for vault execution.
  DELEGATECALL           — delegatecall target as a whitelisted strategy implementing ISharedStrategy.execute().
                           Result is always PositionChange[]: non-empty for LP adds/removes, empty for token-only
                           operations (e.g., harvest, rebalance-swap) where only vault token balances change.
  CALL                   — direct call to a swap aggregator.
                           action.data must be abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata).
                           tokenIn/tokenOut must be distinct vault tokens; output balance delta is checked against minAmountOut.
  CALL_WITH_POSITIONS    — direct call to a target that returns PositionChange[].
                           action.data is the raw calldata forwarded to the target.
                           The result is decoded as PositionChange[] and LP positions are tracked accordingly.
                           INVARIANT: action.target is stored as pos.strategy for any positions added via this
                           path. During withdraw(), exitProportional is always delegatecalled on pos.strategy
                           regardless of how the position was originally created. The target must therefore be a
                           fully-trusted ISharedStrategy implementation — the same requirement as DELEGATECALL.
                           Unlike CALL, no token pre-approval or post-call balance validation is performed;
                           callers must ensure the target only executes authorised LP operations.

```solidity
enum CallType {
  DELEGATECALL,
  CALL,
  CALL_WITH_POSITIONS
}
```

### Unauthorized

```solidity
error Unauthorized()
```

### ZeroAddress

```solidity
error ZeroAddress()
```

### InvalidAmount

```solidity
error InvalidAmount()
```

### InvalidToken

```solidity
error InvalidToken()
```

### InvalidRatio

```solidity
error InvalidRatio()
```

### VaultPaused

```solidity
error VaultPaused()
```

### InvalidTarget

```solidity
error InvalidTarget(address target)
```

### InvalidStrategy

```solidity
error InvalidStrategy(address strategy)
```

### StrategyCallFailed

```solidity
error StrategyCallFailed()
```

### TransferFailed

```solidity
error TransferFailed()
```

### SwapFailed

```solidity
error SwapFailed(uint256 index)
```

### InsufficientShares

```solidity
error InsufficientShares()
```

### InsufficientOutput

```solidity
error InsufficientOutput()
```

### NoTokensConfigured

```solidity
error NoTokensConfigured()
```

### DuplicateToken

```solidity
error DuplicateToken()
```

### TokenNotConfigured

```solidity
error TokenNotConfigured()
```

### CannotSweepVaultToken

```solidity
error CannotSweepVaultToken()
```

### InvalidOperation

```solidity
error InvalidOperation()
```

### LengthMismatch

```solidity
error LengthMismatch()
```

### InvalidVaultOwnerFeeBasisPoint

```solidity
error InvalidVaultOwnerFeeBasisPoint()
```

### InvalidFeeBasisPoint

```solidity
error InvalidFeeBasisPoint()
```

### InvalidGasFeeX64

```solidity
error InvalidGasFeeX64()
```

### NfpmEnumerableRequired

```solidity
error NfpmEnumerableRequired()
```

NFPM must implement `IERC721Enumerable` (`tokenOfOwnerByIndex`) to locate the new token after `CHANGE_RANGE`.

### InvalidNfpm

```solidity
error InvalidNfpm(address nfpm)
```

### InvalidSwapRouter

```solidity
error InvalidSwapRouter(address swapRouter)
```

### TooManyPositions

```solidity
error TooManyPositions()
```

