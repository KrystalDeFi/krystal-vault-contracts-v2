# Solidity API

## SharedPancakeV4ValuationLib

Read-only valuation + fee-growth math for PancakeSwap Infinity CL positions, split out of
        `SharedPancakeV4StrategyLib` to keep that (size-constrained) strategy library under the
        EIP-170 24_576-byte limit. Pure/view only; reads exclusively from the supplied `posm` and
        its CL pool manager. `SharedPancakeV4StrategyLib` exposes thin getter stubs delegating here,
        so the strategy ABI is unchanged. NOTE: separately deployed/linked — deployment and config
        tooling must link it alongside `SharedPancakeV4StrategyLib`.

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

### hasCollectableFeesForFailedCollect

```solidity
function hasCollectableFeesForFailedCollect(address posm, uint256 tokenId) external view returns (bool)
```

_The failed-collect fallback is only a gate for whether to re-revert a hook failure. Use a
     non-wrapping positive-delta check here so feeGrowthInside < feeGrowthInsideLast does not
     look like near-uint256.max pending fees and brick an otherwise zero-fee position. Normal
     valuation still uses `_feeOwed`'s modulo arithmetic to mirror Pancake CL fee accounting._

