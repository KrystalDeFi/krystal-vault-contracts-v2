# Solidity API

## IV4Utils

_Minimal IV4Utils types for encoding exitProportional DECREASE_AND_SWAP instructions.
     Currency = address underneath, so address is used here for ABI-encoding compatibility._

### UtilActions

```solidity
enum UtilActions {
  ADJUST_RANGE,
  DECREASE_AND_SWAP,
  COMPOUND
}
```

### Instructions

```solidity
struct Instructions {
  enum IV4Utils.UtilActions action;
  bytes params;
}
```

### DecreaseLiquidityParams

```solidity
struct DecreaseLiquidityParams {
  uint128 liquidity;
  uint256 deadline;
  uint256 amount0Min;
  uint256 amount1Min;
  bytes hookData;
}
```

### SwapParams

```solidity
struct SwapParams {
  address tokenIn;
  uint256 amountIn;
  address tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### DecreaseAndSwapParams

```solidity
struct DecreaseAndSwapParams {
  struct IV4Utils.DecreaseLiquidityParams decreaseParams;
  struct IV4Utils.SwapParams[] swapParams;
  address swapDestToken;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
}
```

### execute

```solidity
function execute(address posm, uint256 tokenId, struct IV4Utils.Instructions instructions) external
```

## SharedV4Strategy

Uniswap V4 LP operations for SharedVault with token validation and position tracking

### v4UtilsRouter

```solidity
address v4UtilsRouter
```

### OperationType

```solidity
enum OperationType {
  EXECUTE,
  SAFE_TRANSFER_NFT
}
```

### constructor

```solidity
constructor(address _v4UtilsRouter) public
```

### execute

```solidity
function execute(bytes data) external payable returns (struct ISharedStrategy.PositionChange[] changes)
```

Execute an LP operation. Called via delegatecall from SharedVault.

_Strategy MUST validate that pool tokens are vault tokens.
     Since this runs via delegatecall, address(this) is the vault._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| data | bytes | ABI-encoded operation (strategy-specific). V3-style shared strategies (`SharedV3Strategy`,        `SharedAerodromeStrategy`) embed fee Q64 on `IV3Utils` structs:        `protocolFeeX64` / `gasFeeX64` on swap-and-mint and swap-and-increase params, and `performanceFeeX64` /        `gasFeeX64` (plus `liquidityFeeX64` when applicable) on `Instructions` for safe NFT transfer.        See each strategy for the exact tuple after the leading `OperationType` word. `SharedV4Strategy` uses a        different layout. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| changes | struct ISharedStrategy.PositionChange[] | Array of position changes (added/removed) |

### _execute

```solidity
function _execute(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

### _safeTransferNft

```solidity
function _safeTransferNft(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

### depositProportional

```solidity
function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

Add a proportional share of tokens to an existing LP position during vault deposit.

_Uses `INCREASE_LIQUIDITY_FROM_DELTAS` + `CLOSE_CURRENCY` so the PositionManager computes
     the required liquidity from amounts internally. Any unused tokens are swept back to the vault
     by `CLOSE_CURRENCY` (positive delta = take back). Permit2 approval is set inline.
     Slippage is enforced via a pre/post `getPositionLiquidity` comparison: expected liquidity is
     derived from `LiquidityAmounts.getLiquidityForAmounts` at the pre-call sqrtPrice; if the
     actual liquidity added falls below `expectedLiquidity * (1 - slippageBps / 10000)`, reverts._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |
| amount0 | uint256 | Max amount of token0 to add |
| amount1 | uint256 | Max amount of token1 to add |
| slippageBps | uint16 | Slippage tolerance in basis points (e.g. 100 = 1%). Applied as        amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000). Pass 0 for no floor. |

### collectFees

```solidity
function collectFees(address posm, uint256 tokenId, uint16 vaultOwnerFeeBasisPoint) external
```

Pre-collect accumulated LP fees into vault idle balance so they are distributed
        proportionally by share ratio rather than entirely to the next withdrawer.

_Collects accumulated fees via DECREASE_LIQUIDITY(0) + CLOSE_CURRENCY × 2 — a zero-liquidity
     decrease syncs fee accounting without touching principal, and CLOSE_CURRENCY sweeps the fee
     tokens to the vault (address(this) in delegatecall context). Performance and platform fees are
     then applied inline using configManager data, since V4Strategy has no dedicated lpFeeTaker.
     Native ETH currency (address(0)) is handled by wrapping received ETH to WETH after the collect
     so the delta lands in the vault's ERC20 idle balance. If the vault has no WETH configured,
     collection is skipped for that position (falls back to per-withdrawer distribution)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |
| vaultOwnerFeeBasisPoint | uint16 | Vault owner bps for performance fee; platform fee from configManager. |

### exitProportional

```solidity
function exitProportional(address posm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16 vaultOwnerFeeBasisPoint) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Decreases liquidity proportionally via V4UtilsRouter DECREASE_AND_SWAP (no swap).
     Tokens are swept back to the vault (address(this) in delegatecall context) by V4Utils.
     The NFT is returned to the vault by V4Utils after the decrease regardless of exit type.
     Protocol fee (platform) and performance fee (vault owner) are forwarded to V4Utils as X64
     values. V4Utils collects them inline rather than via `LpFeeTaker` (no gas fee on exits)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |
| shares | uint256 | Withdrawer's share count |
| totalShares | uint256 | Total vault share supply (snapshot before burn) |
| minAmount0 | uint256 | Minimum token0 to receive (slippage guard) |
| minAmount1 | uint256 | Minimum token1 to receive (slippage guard) |
| vaultOwnerFeeBasisPoint | uint16 | Vault owner bps for this exit; platform fee from `configManager`. No gas fee on withdraw exits. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| changes | struct ISharedStrategy.PositionChange[] | Empty if partial exit; single removal entry if fully exited |

### getPositionAmounts

```solidity
function getPositionAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Values principal liquidity via `LiquidityAmounts` and current `sqrtPrice` from the v4 PoolManager,
     and uncollected fees via the same `StateLibrary` + fee-growth pattern as v4utils tests (FeeMath).
     Same external-call pattern as `SharedV3Strategy` / Aerodrome / Pancake `getPositionAmounts`:
     no POSM whitelist here; POSM allowlist is enforced on delegatecall paths and when the vault tracks positions._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | Amount of token0 in the position |
| amount1 | uint256 | Amount of token1 in the position |

### getPositionTokens

```solidity
function getPositionTokens(address posm, uint256 tokenId) external view returns (address token0, address token1)
```

Return the canonical token pair for an LP position as recorded on-chain by the NFPM/POSM.

_Used by SharedVault.recoverPosition to validate operator-supplied token0/token1 against the
     actual pool, preventing metadata mismatch that could misprice deposits/withdrawals.
     Called via regular external CALL (not delegatecall) so address(this) is the strategy._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| token0 | address | Canonical pool token0 address |
| token1 | address | Canonical pool token1 address |

### getPositionPrincipalAmounts

```solidity
function getPositionPrincipalAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get *principal-only* token amounts for a tracked LP position, excluding uncollected fees/rewards.

_Returns the token amounts computed purely from the position's in-range liquidity at the current price.
     This is the correct ratio for topping up an existing position via `increaseLiquidity` — uncollected
     fees live in the NFPM as `tokensOwed*` and accrue in a ratio set by historical swap flow, NOT by
     the current price range. Mixing them into the top-up desired amounts would make the
     `amount0Desired : amount1Desired` ratio diverge from the range, so `increaseLiquidity` would either
     (a) consume far less on the "off-ratio" side, leaving dust idle, or
     (b) revert the slippage check when `amount*Min > 0` because the actually consumed amount on the
         binding side falls below the `amount*Min` derived from the desired value.
     SharedVault uses this function (not `getPositionAmounts`) when scaling per-depositor top-ups,
     treating uncollected fees as idle vault balance for share-pricing purposes (they are still counted
     in `getPositionAmounts`, which remains the total-value view).

     Strategies that cannot meaningfully increase liquidity (e.g. staked / locked positions whose
     `depositProportional` returns silently) MAY return (0, 0); the caller skips the LP top-up and
     leaves tokens as idle._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | Principal-only amount of token0 (excludes uncollected fees/rewards) |
| amount1 | uint256 | Principal-only amount of token1 (excludes uncollected fees/rewards) |

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

