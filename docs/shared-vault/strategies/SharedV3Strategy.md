# Solidity API

## SharedV3Strategy

Uniswap V3 LP operations for SharedVault with token validation and position tracking

### v3utils

```solidity
address v3utils
```

### lpFeeTaker

```solidity
address lpFeeTaker
```

### OperationType

```solidity
enum OperationType {
  SWAP_AND_MINT,
  SWAP_AND_INCREASE,
  SAFE_TRANSFER_NFT
}
```

### constructor

```solidity
constructor(address _v3utils, address _lpFeeTaker) public
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

### _swapAndMint

```solidity
function _swapAndMint(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

### _swapAndIncreaseLiquidity

```solidity
function _swapAndIncreaseLiquidity(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

### _safeTransferNft

```solidity
function _safeTransferNft(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

_`CHANGE_RANGE`: Identifies the newly minted token by diffing the vault's pre/post token-ID sets.
     Snapshotting all token IDs before the call and finding the one absent from the snapshot after
     is insertion-order-agnostic: correct regardless of whether V3Utils mints the new NFT before or
     after returning the old one, and regardless of NFPM owner-array ordering.
     A strict post-call balance check (== balanceBefore + 1) enforces that exactly one NFT was minted,
     guarding against multi-mint or burn-and-no-return edge cases._

### collectFees

```solidity
function collectFees(address nfpm, uint256 tokenId, uint16 vaultOwnerFeeBasisPoint) external
```

Pre-collect accumulated LP fees into vault idle balance so they are distributed
        proportionally by share ratio rather than entirely to the next withdrawer.

_Called via delegatecall from SharedVault.withdraw() BEFORE the idle-balance snapshot.
     Implementations should collect fees from the NFPM/POSM and take performance + platform fees
     via the appropriate fee mechanism. Failures are silently ignored by the vault so that a
     collect failure never bricks withdrawals — fee distribution falls back to the old (per-withdrawer)
     behavior._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager (or V4 PositionManager) address |
| tokenId | uint256 | Position NFT ID |
| vaultOwnerFeeBasisPoint | uint16 | Vault owner bps for performance fee; platform fee from configManager. |

### _decreaseVaultPosition

```solidity
function _decreaseVaultPosition(address nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 minAmount0, uint256 minAmount1, address token0, address token1, uint24 fee, uint16 vaultOwnerFeeBasisPoint) internal
```

### exitProportional

```solidity
function exitProportional(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16 vaultOwnerFeeBasisPoint) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Same fee model as public `LpStrategy._decreaseLiquidity`: collect fees → `LpFeeTaker.takeFees`
     (platform + vault owner) → decrease proportional liquidity → collect principal. No V3Utils fee fields._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager |
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

### depositProportional

```solidity
function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

Add a proportional share of tokens to an existing LP position during vault deposit.

_`slippageBps` lowers amount mins from desired (e.g. 100 = 1% tolerance). When 0, mins are
     0 so the pool may consume the usual partial split (see `ISharedStrategy.depositProportional`).
     Out-of-range positions have one desired amount zero, so that side's min stays 0._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager (or V4 PositionManager) address |
| tokenId | uint256 | Position NFT ID |
| amount0 | uint256 | Max amount of token0 to add |
| amount1 | uint256 | Max amount of token1 to add |
| slippageBps | uint16 | Slippage tolerance in basis points (e.g. 100 = 1%). Applied as        amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000). Pass 0 for no floor. |

### getPositionAmounts

```solidity
function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Called via regular CALL (not staticcall) from non-view vault functions such as deposit().
     The function is declared `view` so Solidity prevents state mutation, but the EVM opcode
     used by the caller is CALL, not STATICCALL, when invoked from a non-view context._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager address |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | Amount of token0 in the position |
| amount1 | uint256 | Amount of token1 in the position |

### getPositionTokens

```solidity
function getPositionTokens(address nfpm, uint256 tokenId) external view returns (address token0, address token1)
```

Return the canonical token pair for an LP position as recorded on-chain by the NFPM/POSM.

_Used by SharedVault.recoverPosition to validate operator-supplied token0/token1 against the
     actual pool, preventing metadata mismatch that could misprice deposits/withdrawals.
     Called via regular external CALL (not delegatecall) so address(this) is the strategy._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager (or V4 PositionManager) address |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| token0 | address | Canonical pool token0 address |
| token1 | address | Canonical pool token1 address |

### getPositionPrincipalAmounts

```solidity
function getPositionPrincipalAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
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
| nfpm | address | NFT Position Manager address |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | Principal-only amount of token0 (excludes uncollected fees/rewards) |
| amount1 | uint256 | Principal-only amount of token1 (excludes uncollected fees/rewards) |

### _getPool

```solidity
function _getPool(address nfpm, address token0, address token1, uint24 fee) internal view returns (address)
```

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

### _approveTokens

```solidity
function _approveTokens(address[] _tokens, uint256[] approveAmounts, address target) internal
```

### _revokeTokenApprovals

```solidity
function _revokeTokenApprovals(address[] _tokens, uint256[] approveAmounts, address target) internal
```

