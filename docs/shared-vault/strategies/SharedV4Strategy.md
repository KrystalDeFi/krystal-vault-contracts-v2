# Solidity API

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

_Strategy MUST validate that pool tokens are vault tokens by calling
     ISharedVault(address(this)).isVaultToken(token) for each pool token.
     Since this runs via delegatecall, address(this) is the vault.
     Strategy MUST return position changes so the vault can track LP positions._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| data | bytes | Encoded operation params (strategy-specific) |

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

