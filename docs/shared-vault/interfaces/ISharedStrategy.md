# Solidity API

## ISharedStrategy

### InvalidPoolTokens

```solidity
error InvalidPoolTokens()
```

### PositionChange

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
| data | bytes | Encoded operation params (strategy-specific). V3-style strategies append        `(uint16 platformFeeBps, uint64 gasFeeX64)` after swap/mint, swap/increase, and safe-transfer payloads.        Platform `0` uses `configManager.platformFeeBasisPoint()`; gas is used as passed. |

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
| vaultOwnerFeeBasisPoint | uint16 | Vault owner bps for this exit; platform fee from `configManager`. No gas fee on withdraw exits. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| changes | struct ISharedStrategy.PositionChange[] | Empty if partial exit; single removal entry if fully exited |

### depositProportional

```solidity
function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1) external
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

### getPositionAmounts

```solidity
function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Called via regular staticcall from the vault._

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

