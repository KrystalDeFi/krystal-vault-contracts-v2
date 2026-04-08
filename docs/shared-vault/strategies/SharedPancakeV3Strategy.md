# Solidity API

## SharedPancakeV3Strategy

PancakeSwap V3 LP + MasterChef farming for SharedVault with token validation and position tracking

### v3utils

```solidity
address v3utils
```

### lpFeeTaker

```solidity
address lpFeeTaker
```

### masterChefV3

```solidity
address masterChefV3
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
  DEPOSIT_MASTERCHEF,
  WITHDRAW_MASTERCHEF,
  HARVEST_MASTERCHEF
}
```

### constructor

```solidity
constructor(address _v3utils, address _lpFeeTaker, address _masterChefV3, address _configManager) public
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

_For CHANGE_RANGE: caller must provide newTokenId (the NFT minted by V3Utils for the new position)._

### _depositMasterChef

```solidity
function _depositMasterChef(bytes data) internal
```

### _withdrawMasterChef

```solidity
function _withdrawMasterChef(bytes data) internal
```

### _harvestMasterChef

```solidity
function _harvestMasterChef(bytes data) internal
```

### _harvestRewards

```solidity
function _harvestRewards(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal
```

### _decreaseVaultPosition

```solidity
function _decreaseVaultPosition(address _nfpm, uint256 tokenId, uint128 liquidityToRemove, uint256 minAmount0, uint256 minAmount1, address token0, address token1, uint24 fee, uint16 vaultOwnerFeeBasisPoint) internal
```

_Splits NFPM decrease to keep `exitProportional` stack shallow for IR builds._

### exitProportional

```solidity
function exitProportional(address _nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1, uint16 vaultOwnerFeeBasisPoint) external returns (struct ISharedStrategy.PositionChange[] changes)
```

Exit a proportional share of an LP position during vault withdrawal.

_Handles both direct (vault-held) and MasterChef-staked positions.
     Proportional exit uses NFPM + `LpFeeTaker` like public `LpStrategy` (not V3Utils performance fees)._

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

### depositProportional

```solidity
function depositProportional(address _nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

Add a proportional share of tokens to an existing LP position during vault deposit.

_Handles MasterChef-staked positions: harvests rewards, withdraws from MasterChef,
     increases liquidity, then re-deposits. Non-zero `slippageBps` sets amount mins; 0 = no floor._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Position NFT ID |
| amount0 | uint256 | Max amount of token0 to add |
| amount1 | uint256 | Max amount of token1 to add |
| slippageBps | uint16 | Slippage tolerance in basis points (e.g. 100 = 1%). Applied as        amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000). Pass 0 for no floor. |

### getPositionAmounts

```solidity
function getPositionAmounts(address _nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

Get token amounts for a tracked LP position (liquidity + uncollected fees)

_Called via regular CALL (not staticcall) from non-view vault functions such as deposit().
     The function is declared `view` so Solidity prevents state mutation, but the EVM opcode
     used by the caller is CALL, not STATICCALL, when invoked from a non-view context._

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
function _getPool(address _nfpm, address token0, address token1, uint24 fee) internal view returns (address)
```

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

### _approveTokens

```solidity
function _approveTokens(address[] _tokens, uint256[] approveAmounts, address target) internal
```

