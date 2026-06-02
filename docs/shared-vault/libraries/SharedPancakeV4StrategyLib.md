# Solidity API

## SharedPancakeV4StrategyLib

### depositProportional

```solidity
function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

_See SharedV4StrategyLib.depositProportional for the full slippage rationale. The previous
     liquidity post-check compared the requested liquidity against a fraction of itself and was
     always satisfied; this enforces a real per-token floor on the amounts ACTUALLY consumed
     (balance deltas) against the amounts quoted for `liquidityToAdd`, with the `slippageBps`
     haircut, and tolerates single-sided positions. It cannot by itself defeat a cross-tx spot
     sandwich (adding CL liquidity does not move price), so callers must pass a conservative bps._

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

_Returns `params` with its leading 4-byte selector stripped, as a FRESH buffer.
     Non-destructive: the caller's `params` is left byte-for-byte intact. (The previous
     in-place variant aliased `params + 4` and rewrote its length word + selector, which was
     a latent footgun for any future caller that read `params` afterward.) Costs one
     allocation plus an `mcopy` of the tail — negligible against the V4 operation it precedes._

