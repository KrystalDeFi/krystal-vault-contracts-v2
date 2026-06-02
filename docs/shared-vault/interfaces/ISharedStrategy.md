# Solidity API

## ISharedStrategy

### InvalidPoolTokens

```solidity
error InvalidPoolTokens()
```

### PositionChange

_Shared strategies validate pool currencies against SharedVault's ERC20 token set.
     Because vault token slots use `address(0)` as "unused", native-currency V4/Pancake pools
     where a currency unwraps to `address(0)` are unsupported. Use wrapped-native ERC20 pools._

```solidity
struct PositionChange {
  bool isAdd;
  address nfpm;
  uint256 tokenId;
  address token0;
  address token1;
}
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

### exitProportional

```solidity
function exitProportional(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16 vaultOwnerFeeBasisPoint) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Called via delegatecall from SharedVault.withdraw so address(this) is the vault.
     Must remove `shares/totalShares` of the position's liquidity, collect fees,
     and leave resulting tokens in the vault. Returns position changes so the vault
     can untrack the position if fully exited._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT Position Manager |
| tokenId | uint256 | Position NFT ID |
| shares | uint256 | Withdrawer's share count |
| totalShares | uint256 | Total vault share supply (snapshot before burn) |
| minAmount0 | uint256 | Minimum token0 to receive (slippage guard) |
| minAmount1 | uint256 | Minimum token1 to receive (slippage guard) |
| vaultOwnerFeeBasisPoint | uint16 | Deprecated compatibility argument. Implementations must read vault-owner bps from the vault. @return changes Empty if partial exit; single removal entry if fully exited |

### depositProportional

```solidity
function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
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

### collectFees

```solidity
function collectFees(address nfpm, uint256 tokenId, uint16 vaultOwnerFeeBasisPoint) external
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
| vaultOwnerFeeBasisPoint | uint16 | Deprecated compatibility argument. Implementations must read vault-owner bps from the vault. |

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

