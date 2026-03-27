# Solidity API

## SharedAerodromeStrategy

Aerodrome CL LP + gauge farming for SharedVault with token validation

_Executed via delegatecall from SharedVault. Validates pool tokens are vault tokens._

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
function execute(bytes data) external payable
```

Execute an LP operation. Called via delegatecall from SharedVault.

_Strategy MUST validate that pool tokens are vault tokens by calling
     ISharedVault(address(this)).isVaultToken(token) for each pool token.
     Since this runs via delegatecall, address(this) is the vault._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| data | bytes | Encoded operation params (strategy-specific) |

### _swapAndMint

```solidity
function _swapAndMint(bytes data) internal
```

### _swapAndIncreaseLiquidity

```solidity
function _swapAndIncreaseLiquidity(bytes data) internal
```

### _safeTransferNft

```solidity
function _safeTransferNft(bytes data) internal
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

