# Solidity API

## SharedV4Strategy

Uniswap V4 LP operations for SharedVault with token validation

_Executed via delegatecall from SharedVault. Validates pool tokens are vault tokens._

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

### _execute

```solidity
function _execute(bytes data) internal
```

### _safeTransferNft

```solidity
function _safeTransferNft(bytes data) internal
```

### _validateVaultToken

```solidity
function _validateVaultToken(address token) internal view
```

