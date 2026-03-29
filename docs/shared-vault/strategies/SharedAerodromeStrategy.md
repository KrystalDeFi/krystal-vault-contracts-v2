# Solidity API

## SharedAerodromeStrategy

Aerodrome CL LP + gauge farming for SharedVault with token validation and position tracking

### v3utils

```solidity
address v3utils
```

### gaugeFactory

```solidity
address gaugeFactory
```

### nfpm

```solidity
address nfpm
```

### configManager

```solidity
contract ISharedConfigManager configManager
```

### OperationType

```solidity
enum OperationType {
  SWAP_AND_MINT,
  SWAP_AND_INCREASE,
  SAFE_TRANSFER_NFT,
  DEPOSIT_GAUGE,
  WITHDRAW_GAUGE,
  HARVEST_GAUGE
}
```

### constructor

```solidity
constructor(address _v3utils, address _gaugeFactory, address _configManager) public
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

_For CHANGE_RANGE: caller must provide newTokenId (the NFT minted by V3Utils for the new position)._

### _depositGauge

```solidity
function _depositGauge(bytes data) internal
```

### _withdrawGauge

```solidity
function _withdrawGauge(bytes data) internal
```

### _harvestGauge

```solidity
function _harvestGauge(bytes data) internal
```

### _harvestRewards

```solidity
function _harvestRewards(address clGauge, uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal
```

### getPositionAmounts

```solidity
function getPositionAmounts(address _nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Called via regular staticcall from the vault. Strategy uses its own
     protocol-specific interfaces for precise valuation._

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

### _getPool

```solidity
function _getPool(address token0, address token1, int24 tickSpacing) internal view returns (address)
```

### _getGaugeFromTokenId

```solidity
function _getGaugeFromTokenId(uint256 tokenId) internal view returns (address gauge)
```

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

### _approveTokens

```solidity
function _approveTokens(address[] _tokens, uint256[] approveAmounts, address target) internal
```

