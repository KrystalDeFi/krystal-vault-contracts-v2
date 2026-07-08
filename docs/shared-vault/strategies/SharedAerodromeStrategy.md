# Solidity API

## SharedAerodromeStrategy

Aerodrome CL LP operations for SharedVault with token validation and position tracking.
        Uses Aerodrome's tickSpacing-based pool lookup (ICLFactory.getPool(address,address,int24))
        instead of Uniswap V3's fee-based lookup — the only structural difference from SharedV3Strategy.

### SwapAndMint

```solidity
event SwapAndMint(address nfpm, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
```

### SwapAndIncreaseLiquidity

```solidity
event SwapAndIncreaseLiquidity(address nfpm, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
```

### CompoundFees

```solidity
event CompoundFees(address nfpm, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
```

### ChangeRange

```solidity
event ChangeRange(address nfpm, uint256 tokenId, uint256 newTokenId, uint256 newLiquidity, uint256 token0Added, uint256 token1Added)
```

### WithdrawAndCollectAndSwap

```solidity
event WithdrawAndCollectAndSwap(address nfpm, uint256 tokenId, address token, uint256 amount)
```

_`token`/`amount` report `instructions.targetToken` and this operation's proceeds in it
     (0 when no target token is set). Unlike v3utils nothing is transferred out — the
     proceeds stay idle in the vault._

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

_Despite the historical `SAFE_TRANSFER_NFT` name, the NFT itself is never transferred —
     the strategy mutates the position in-place._

### collectFees

```solidity
function collectFees(address _nfpm, uint256 tokenId, uint16) external
```

Collect accumulated LP fees into vault idle balance and settle performance/platform fees.

_Called via delegatecall from SharedVault.withdraw() BEFORE the idle-balance snapshot. Strategy execute
     paths also call their internal collect logic before mutating an existing position. Implementations
     should collect fees from the NFPM/POSM and take performance + platform fees via the appropriate
     fee mechanism._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |
|  | uint16 |  |

### _collectFees

```solidity
function _collectFees(address _nfpm, uint256 tokenId, struct ICommon.FeeConfig perfFee) internal
```

### _decreaseVaultPosition

```solidity
function _decreaseVaultPosition(address _nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 minAmount0, uint256 minAmount1, address token0, address token1) internal
```

### exitProportional

```solidity
function exitProportional(address _nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Called via delegatecall from SharedVault.withdraw so address(this) is the vault.
     Must remove `shares/totalShares` of the position's liquidity, collect fees,
     and leave resulting tokens in the vault. Returns position changes so the vault
     can untrack the position if fully exited._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |
| shares | uint256 | Withdrawer's share count |
| totalShares | uint256 | Total vault share supply (snapshot before burn) |
| minAmount0 | uint256 | Minimum token0 to receive (slippage guard) |
| minAmount1 | uint256 | Minimum token1 to receive (slippage guard) |
|  | uint16 |  |

### getPositionAmounts

```solidity
function getPositionAmounts(address _nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Not gated by configManager whitelist — called via external CALL from the vault (not delegatecall),
     so `address(this)` is the strategy; NFPM trust is enforced on all mutating delegatecall paths._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | Amount of token0 in the position |
| amount1 | uint256 | Amount of token1 in the position |

### getPositionTokens

```solidity
function getPositionTokens(address _nfpm, uint256 tokenId) external view returns (address token0, address token1)
```

Return the canonical token pair for an LP position as recorded on-chain by the NFPM/POSM.

_Used by SharedVault.recoverPosition to validate operator-supplied token0/token1 against the
     actual pool, preventing metadata mismatch that could misprice deposits/withdrawals.
     Called via regular external CALL (not delegatecall) so address(this) is the strategy._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| token0 | address | Canonical pool token0 address |
| token1 | address | Canonical pool token1 address |

### getPositionPrincipalAmounts

```solidity
function getPositionPrincipalAmounts(address _nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
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
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | Principal-only amount of token0 (excludes uncollected fees/rewards) |
| amount1 | uint256 | Principal-only amount of token1 (excludes uncollected fees/rewards) |

### getPositionAmountsSplit

```solidity
function getPositionAmountsSplit(address _nfpm, uint256 tokenId) external view returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
```

Get gross and principal-only token amounts for a tracked LP position in one valuation pass.

_`total*` includes principal plus uncollected fees/rewards. `principal*` excludes uncollected
     fees/rewards. Callers that need both values should use this function instead of calling
     `getPositionAmounts` and `getPositionPrincipalAmounts` separately._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| total0 | uint256 | Gross token0 amount in the position |
| total1 | uint256 | Gross token1 amount in the position |
| principal0 | uint256 | Principal-only token0 amount |
| principal1 | uint256 | Principal-only token1 amount |

### depositProportional

```solidity
function depositProportional(address _nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

Add a proportional share of tokens to an existing LP position during vault deposit.

_Called via delegatecall from SharedVault.deposit so address(this) is the vault.
     Increases liquidity with the given amounts; tokens not consumed by the position
     (due to price range mismatch) remain as idle vault balance automatically.
     Implementations that cannot increase liquidity (e.g. MasterChef-staked positions)
     MUST return silently — the caller leaves unused tokens as idle._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |
| amount0 | uint256 | Max amount of token0 to add |
| amount1 | uint256 | Max amount of token1 to add |
| slippageBps | uint16 | Slippage tolerance in basis points (e.g. 100 = 1%). Applied as        amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000). Pass 0 for no floor. |

### _getPool

```solidity
function _getPool(address _nfpm, address token0, address token1, int24 tickSpacing) internal view returns (address)
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
     per-hop inside `_swap` against the immutable `swapRouter`. `approveTokens` is walked here
     purely to enforce that EVERY entry references a vault-tracked token (including zero-amount
     entries), blocking operators from listing unrelated tokens through this entry point._

