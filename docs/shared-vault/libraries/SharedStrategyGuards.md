# Solidity API

## SharedStrategyGuards

NFPM whitelist checks for SharedVault strategies (defense in depth vs vault-level checks).

### requireWhitelistedNfpm

```solidity
function requireWhitelistedNfpm(contract ISharedConfigManager cm, address nfpm) internal view
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| cm | contract ISharedConfigManager |  |
| nfpm | address | NFT / position manager address (V3 NFPM or V4 position manager) |

