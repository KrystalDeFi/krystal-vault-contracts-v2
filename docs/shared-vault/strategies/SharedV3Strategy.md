# Solidity API

## SharedV3Strategy

Uniswap V3 LP operations for SharedVault with token validation

_Executed via delegatecall from SharedVault. Validates pool tokens are vault tokens._

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

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

### _approveTokens

```solidity
function _approveTokens(address[] _tokens, uint256[] approveAmounts, address target) internal
```

