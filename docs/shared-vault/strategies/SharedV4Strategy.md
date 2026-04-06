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
| data | bytes | Encoded operation params (strategy-specific). V3-style strategies append        `(uint16 platformFeeBps, uint64 gasFeeX64)` after swap/mint, swap/increase, and safe-transfer payloads.        Platform `0` uses `configManager.platformFeeBasisPoint()`; gas is used as passed. |

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

### exitProportional

```solidity
function exitProportional(address posm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, struct ISharedStrategy.ExitProportionalFeeParams feeParams) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Decreases liquidity proportionally via V4UtilsRouter DECREASE_AND_SWAP (no swap).
     Tokens are swept back to the vault (address(this) in delegatecall context) by V4Utils.
     The NFT is returned to the vault by V4Utils after the decrease regardless of exit type.
     Protocol/performance fees are left at zero here: V4Utils does not integrate with `LpFeeTaker`;
     use vault-level fee config + future v4 fee plumbing if needed._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| posm | address |  |
| tokenId | uint256 | Position NFT ID |
| shares | uint256 | Withdrawer's share count |
| totalShares | uint256 | Total vault share supply (snapshot before burn) |
| minAmount0 | uint256 | Minimum token0 to receive (slippage guard) |
| minAmount1 | uint256 | Minimum token1 to receive (slippage guard) |
| feeParams | struct ISharedStrategy.ExitProportionalFeeParams | Vault owner bps for this exit; platform fee from `configManager`. No gas fee on withdraw exits. |

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
     and uncollected fees via the same `StateLibrary` + fee-growth pattern as v4utils tests (FeeMath)._

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

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

