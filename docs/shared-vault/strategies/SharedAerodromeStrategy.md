# Solidity API

## SharedAerodromeStrategy

Aerodrome CL LP + gauge farming for SharedVault with token validation and position tracking

### v3utils

```solidity
address v3utils
```

### lpFeeTaker

```solidity
address lpFeeTaker
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
constructor(address _v3utils, address _lpFeeTaker, address _gaugeFactory, address _configManager) public
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
| data | bytes | ABI-encoded operation (strategy-specific). V3-style shared strategies (`SharedV3Strategy`,        `SharedPancakeV3Strategy`, `SharedAerodromeStrategy`) embed fee Q64 on `IV3Utils` structs:        `protocolFeeX64` / `gasFeeX64` on swap-and-mint and swap-and-increase params, and `performanceFeeX64` /        `gasFeeX64` (plus `liquidityFeeX64` when applicable) on `Instructions` for safe NFT transfer.        See each strategy for the exact tuple after the leading `OperationType` word. `SharedV4Strategy` uses a        different layout. |

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

### _decreaseVaultPosition

```solidity
function _decreaseVaultPosition(address _nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 minAmount0, uint256 minAmount1, address token0, address token1, int24 tickSpacing, uint16 vaultOwnerFeeBasisPoint) internal
```

### exitProportional

```solidity
function exitProportional(address _nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16 vaultOwnerFeeBasisPoint) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Handles gauge-staked and direct positions. Proportional exit: NFPM + `LpFeeTaker` (public LpStrategy pattern)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
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

### getPositionAmounts

```solidity
function getPositionAmounts(address _nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Same external-call contract as `SharedV3Strategy.getPositionAmounts`: the vault invokes this with
     `ISharedStrategy(strategy).getPositionAmounts` (not delegatecall), so we do **not** apply
     `configManager` whitelist here — de-whitelisting an NFPM must not brick `deposit` / previews that
     only need valuation. Canonical NFPM is still implied by vault-tracked positions; whitelist +
     `_nfpm == nfpm` remain on all mutating / delegatecall paths._

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

### depositProportional

```solidity
function depositProportional(address _nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

Add a proportional share of tokens to an existing LP position during vault deposit.

_Handles gauge-staked positions: unstakes before increasing liquidity, then restakes.
     Non-zero `slippageBps` sets amount mins below desired; 0 means no floor (see `ISharedStrategy`)._

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

