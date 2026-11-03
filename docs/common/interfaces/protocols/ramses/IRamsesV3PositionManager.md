# Solidity API

## IRamsesV3PositionManager

Ramses' CL position manager (RamsesV3PositionManager). Uniswap V3's NFPM keyed by tick spacing, with a
        10-field `positions` (no nonce/operator), an 11-field `mint` (no sqrtPriceX96) and gauge-reward claiming.
        Unlike Uniswap V3, `increaseLiquidity` is gated to the position's owner or approved operators, and both
        `increaseLiquidity` and `decreaseLiquidity` claim the position's pending RAM/xRAM to the NFT's current
        owner before restarting its anti-sybil timer (`positionLastModified`).

### MintParams

```solidity
struct MintParams {
  address token0;
  address token1;
  int24 tickSpacing;
  int24 tickLower;
  int24 tickUpper;
  uint256 amount0Desired;
  uint256 amount1Desired;
  uint256 amount0Min;
  uint256 amount1Min;
  address recipient;
  uint256 deadline;
}
```

### IncreaseLiquidityParams

```solidity
struct IncreaseLiquidityParams {
  uint256 tokenId;
  uint256 amount0Desired;
  uint256 amount1Desired;
  uint256 amount0Min;
  uint256 amount1Min;
  uint256 deadline;
}
```

### DecreaseLiquidityParams

```solidity
struct DecreaseLiquidityParams {
  uint256 tokenId;
  uint128 liquidity;
  uint256 amount0Min;
  uint256 amount1Min;
  uint256 deadline;
}
```

### CollectParams

```solidity
struct CollectParams {
  uint256 tokenId;
  address recipient;
  uint128 amount0Max;
  uint128 amount1Max;
}
```

### positions

```solidity
function positions(uint256 tokenId) external view returns (address token0, address token1, int24 tickSpacing, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1)
```

### mint

```solidity
function mint(struct IRamsesV3PositionManager.MintParams params) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
```

### increaseLiquidity

```solidity
function increaseLiquidity(struct IRamsesV3PositionManager.IncreaseLiquidityParams params) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1)
```

### decreaseLiquidity

```solidity
function decreaseLiquidity(struct IRamsesV3PositionManager.DecreaseLiquidityParams params) external payable returns (uint256 amount0, uint256 amount1)
```

### collect

```solidity
function collect(struct IRamsesV3PositionManager.CollectParams params) external payable returns (uint256 amount0, uint256 amount1)
```

### getReward

```solidity
function getReward(uint256 tokenId, address[] tokens) external
```

Claim the position's gauge rewards in `tokens` to the NFT's owner.

_Callable by the owner or an approved operator. Reverts when the position's pool has no gauge. A claim the
     gauge's reward validator flags (anti-sybil timer, blacklists) is forfeited, not paid, and doesn't revert._

### positionLastModified

```solidity
function positionLastModified(uint256 tokenId) external view returns (uint32)
```

Timestamp of the position's last liquidity change: the anti-sybil timer's checkpoint.

### deployer

```solidity
function deployer() external view returns (address)
```

The RamsesV3PoolDeployer pools are deployed by.

### ownerOf

```solidity
function ownerOf(uint256 tokenId) external view returns (address)
```

