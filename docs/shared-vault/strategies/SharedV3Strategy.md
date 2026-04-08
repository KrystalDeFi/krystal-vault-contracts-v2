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
| data | bytes | Encoded operation params (strategy-specific). V3-style strategies append        `(uint16 platformFeeBps, uint64 gasFeeX64)` after swap/mint, swap/increase, and safe-transfer payloads.        Platform `0` uses `configManager.platformFeeBasisPoint()`; gas is used as passed. |

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

