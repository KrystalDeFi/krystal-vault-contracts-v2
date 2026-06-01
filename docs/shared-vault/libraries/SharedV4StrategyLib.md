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

