# Solidity API

## SharedPancakeV4Strategy

PancakeSwap V4 LP operations for SharedVault with token validation and position tracking

### swapRouter

```solidity
address swapRouter
```

### OperationType

```solidity
enum OperationType {
  EXECUTE,
  EXECUTE_INSTRUCTIONS
}
```

### constructor

```solidity
constructor(address _swapRouter) public
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
| data | bytes | ABI-encoded operation (strategy-specific). V3-style shared strategies (`SharedV3Strategy`,        `SharedAerodromeStrategy`) use `IV3Utils`-compatible structs but execute natively in the strategy.        `SharedV4Strategy` and `SharedPancakeV4Strategy` accept protocol-specific V4Utils-compatible        instructions and execute them natively through the relevant PositionManager. Utility fee fields remain        API-controlled; platform and owner fees are read from shared-vault config and vault state. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| changes | struct ISharedStrategy.PositionChange[] | Array of position changes (added/removed) |

### _execute

```solidity
function _execute(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

_`approveTokens` / `approveAmounts` are kept for ABI backward-compatibility but are NOT
     used for ERC20 approvals. Approvals are issued per-hop inside `_swapV4` against the
     immutable `swapRouter`. These arrays are still walked by `_validateApprovalList` to
     enforce that any positive-amount entry references a vault-tracked token, which prevents
     operators from silently sneaking unrelated tokens through this entry point._

### _executeInstructions

```solidity
function _executeInstructions(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

_Executes the encoded instruction bytes inline against the position; despite the
     historical name `SAFE_TRANSFER_NFT`, the NFT itself is never transferred — the strategy
     operates on the position in-place via the shared lib._

### depositProportional

```solidity
function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

Add a proportional share of tokens to an existing LP position during vault deposit.

_Uses `INCREASE_LIQUIDITY` + `CLOSE_CURRENCY` so the PositionManager pulls the exact
     amounts required for the computed liquidity through Permit2. Any amount not needed for
     the current pool/range ratio stays idle in the vault. Permit2 approval is set inline.
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
function collectFees(address posm, uint256 tokenId, uint16) external
```

Collect accumulated LP fees into vault idle balance and settle performance/platform fees.

_Collects accumulated fees via CL_DECREASE_LIQUIDITY(0) + TAKE_PAIR — a zero-liquidity
     decrease syncs fee growth without touching principal; TAKE_PAIR sweeps accumulated fees
     to the vault (address(this) in delegatecall context). Performance and platform fees are
     then applied inline since V4Strategy has no dedicated lpFeeTaker.
     Native ETH positions (currency address(0)) are rejected at position-add time by
     _validateVaultToken, so this function is never called for native-currency pools._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |
|  | uint16 |  |

### exitProportional

```solidity
function exitProportional(address posm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Withdraw exits collect generated LP fees through collectFees() before the vault's idle snapshot.
     This function only decreases principal natively and never charges platform/owner fees on principal._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |
| shares | uint256 | Withdrawer's share count |
| totalShares | uint256 | Total vault share supply (snapshot before burn) |
| minAmount0 | uint256 | Minimum token0 to receive (slippage guard) |
| minAmount1 | uint256 | Minimum token1 to receive (slippage guard) |
|  | uint16 |  |

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

