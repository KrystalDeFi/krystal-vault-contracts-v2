# Solidity API

## SharedV3Strategy

Uniswap V3 LP operations for SharedVault with token validation and position tracking

### swapRouter

```solidity
address swapRouter
```

### OperationType

```solidity
enum OperationType {
  SWAP_AND_MINT,
  SWAP_AND_INCREASE,
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

### _swapAndMint

```solidity
function _swapAndMint(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

### _swapAndIncreaseLiquidity

```solidity
function _swapAndIncreaseLiquidity(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

### _executeInstructions

```solidity
function _executeInstructions(bytes data) internal returns (struct ISharedStrategy.PositionChange[] changes)
```

_Native V3Utils-style action execution. Generated LP fees are collected only for actions
     that naturally consume fees. Platform and owner fees are taken from generated LP fees;
     gas fee is taken from generated fees and, when liquidity is decreased, from principal too.
     Despite the historical `SAFE_TRANSFER_NFT` name, the NFT itself is never transferred —
     the strategy mutates the position in-place._

### collectFees

```solidity
function collectFees(address nfpm, uint256 tokenId, uint16) external
```

Collect accumulated LP fees into vault idle balance and settle performance/platform fees.

_Called via delegatecall from SharedVault.withdraw() BEFORE the idle-balance snapshot. Strategy execute
     paths also call their internal collect logic before mutating an existing position. Implementations
     should collect fees from the NFPM/POSM and take performance + platform fees via the appropriate
     fee mechanism._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager (or V4 PositionManager) address |
| tokenId | uint256 | Position NFT ID |
|  | uint16 |  |

### _collectFees

```solidity
function _collectFees(address nfpm, uint256 tokenId, struct ICommon.FeeConfig perfFee) internal
```

### _decreaseVaultPosition

```solidity
function _decreaseVaultPosition(address nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 minAmount0, uint256 minAmount1, address token0, address token1) internal
```

### exitProportional

```solidity
function exitProportional(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Fee model: collect fees → take platform + vault-owner fees (direct transfer via
     `SharedStrategyFees`) → decrease proportional liquidity → collect principal. No V3Utils fee fields._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager |
| tokenId | uint256 | Position NFT ID |
| shares | uint256 | Withdrawer's share count |
| totalShares | uint256 | Total vault share supply (snapshot before burn) |
| minAmount0 | uint256 | Minimum token0 to receive (slippage guard) |
| minAmount1 | uint256 | Minimum token1 to receive (slippage guard) |
|  | uint16 |  |

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
     SharedVault uses this function (not `getPositionAmounts`) when scaling per-depositor top-ups.
     Uncollected fees are treated as idle-like value for share pricing, but only net of platform and
     vault-owner performance fees; `getPositionAmounts` remains the gross position-value view.

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

### _validateApprovalList

```solidity
function _validateApprovalList(address[] _tokens, uint256[] approveAmounts) internal view
```

_`approveTokens` / `approveAmounts` are NOT used to issue ERC20 approvals — those happen
     per-hop inside `_swap` against the immutable `swapRouter`. They are walked here purely
     to enforce that any positive-amount entry references a vault-tracked token, blocking
     operators from sneaking unrelated tokens through this entry point._

