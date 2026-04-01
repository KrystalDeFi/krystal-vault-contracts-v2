# Solidity API

## INFPM

_Generic NFPM for querying positions_

### positions

```solidity
function positions(uint256 tokenId) external view returns (uint96, address, address token0, address token1, int24 feeOrTickSpacing, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256, uint256, uint128, uint128)
```

### factory

```solidity
function factory() external view returns (address)
```

## IUniV3Factory

_UniswapV3 factory for pool lookup (fee as uint24)_

### getPool

```solidity
function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address)
```

## IUniV3Pool

_UniswapV3 pool for slot0 query_

### slot0

```solidity
function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)
```

## SharedV3Strategy

Uniswap V3 LP operations for SharedVault with token validation and position tracking

### v3utils

```solidity
address v3utils
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
constructor(address _v3utils) public
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
| data | bytes | Encoded operation params (strategy-specific) |

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

_For CHANGE_RANGE: caller must provide newTokenId (the NFT minted by V3Utils for the new position).
     The caller can predict this via NFPM._nextId() or tx simulation._

### exitProportional

```solidity
function exitProportional(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1) external returns (struct ISharedStrategy.PositionChange[] changes)
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

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| changes | struct ISharedStrategy.PositionChange[] | Empty if partial exit; single removal entry if fully exited |

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

