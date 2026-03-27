# Solidity API

## ISharedStrategy

### InvalidPoolTokens

```solidity
error InvalidPoolTokens()
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

