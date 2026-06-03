# Solidity API

## SharedV4StrategyLib

### depositProportional

```solidity
function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

_Slippage model: the previous implementation requested EXACTLY `liquidityToAdd` and then
     checked `liquidityAdded >= liquidityToAdd * (1 - bps)` — always true, so it provided no
     protection. This version enforces a real per-token floor on the amounts ACTUALLY consumed
     (measured via balance deltas) against the amounts quoted for `liquidityToAdd` at the
     current price, with the `slippageBps` haircut. The floor is computed from
     `getAmountsForLiquidity` (not the raw supplied `amount0/amount1`) so single-sided /
     out-of-range positions — where one side is legitimately ~0 — do not spuriously revert.
     NOTE: adding CL liquidity does not move the pool price, so within one tx `used == expected`;
     this floor catches a misbehaving/non-canonical position manager but cannot by itself defeat
     a CROSS-transaction spot-price sandwich. Callers must pass a conservative `slippageBps` and,
     where MEV is a concern, derive the deposit ratio from an external price reference._

### collectFees

```solidity
function collectFees(address posm, uint256 tokenId, struct ICommon.FeeConfig fc) external
```

### executeCalldata

```solidity
function executeCalldata(address swapRouter, address posm, uint256 tokenId, bytes params) external
```

### executeInstructionBytes

```solidity
function executeInstructionBytes(address swapRouter, address posm, uint256 tokenId, bytes instruction) external
```

### swapAndMintCalldata

```solidity
function swapAndMintCalldata(address swapRouter, address posm, bytes params) external
```

### swapAndIncreaseCalldata

```solidity
function swapAndIncreaseCalldata(address swapRouter, address posm, uint256 tokenId, bytes params) external
```

### exitProportional

```solidity
function exitProportional(address posm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1) external returns (struct ISharedStrategy.PositionChange[] changes)
```

### getPositionAmounts

```solidity
function getPositionAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

### getPositionPrincipalAmounts

```solidity
function getPositionPrincipalAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

### getPositionAmountsSplit

```solidity
function getPositionAmountsSplit(address posm, uint256 tokenId) external view returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
```

### _v4ParamsSelector

```solidity
function _v4ParamsSelector(bytes params) internal pure returns (bytes4 selector)
```

### _v4ParamsBody

```solidity
function _v4ParamsBody(bytes params) internal pure returns (bytes body)
```

_Returns `params` with its leading 4-byte selector stripped, as a FRESH buffer — the caller's
     `params` is left byte-for-byte intact (unlike the former in-place variant that aliased
     `params + 4` and clobbered its length word + selector). Allocated by hand rather than via
     `new bytes` to skip the redundant zero-fill (mcopy overwrites it anyway), which keeps this
     size-constrained library further under the EIP-170 limit. Mechanics:
       - `body` := free-memory pointer; store the new length `len - 4` at `body`.
       - mcopy the tail: source skips params' length word (0x20) and selector (0x04) => `params + 0x24`.
       - advance the free pointer by 0x20 (length word) + data rounded up to a 32-byte word.
     `mcopy` copies exactly `bodyLen` bytes, so non-word-aligned tails neither over-read `params` nor
     over-write `body`. Covered by SharedV4ParamsDecode.t.sol (non-mutation, fuzz, unaligned, empty)._

