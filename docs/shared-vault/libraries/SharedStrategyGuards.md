# Solidity API

## SharedStrategyGuards

NFPM and swap-router whitelist checks for SharedVault strategies (defense in depth vs vault-level checks).

### requireWhitelistedNfpm

```solidity
function requireWhitelistedNfpm(contract ISharedConfigManager cm, address nfpm) internal view
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| cm | contract ISharedConfigManager |  |
| nfpm | address | NFT / position manager address (V3 NFPM or V4 position manager) |

### requireWhitelistedOxSwapData

```solidity
function requireWhitelistedOxSwapData(contract ISharedConfigManager cm, bytes swapData) internal view
```

_V3Utils swap calldata is `abi.encode(allowanceTarget, data)` per `IV3Utils` (0x-style router + calldata)._

### requireWhitelistedV3SwapRoutersSwapAndMint

```solidity
function requireWhitelistedV3SwapRoutersSwapAndMint(contract ISharedConfigManager cm, struct IV3Utils.SwapAndMintParams p) internal view
```

### requireWhitelistedV3SwapRoutersSwapAndIncrease

```solidity
function requireWhitelistedV3SwapRoutersSwapAndIncrease(contract ISharedConfigManager cm, struct IV3Utils.SwapAndIncreaseLiquidityParams p) internal view
```

### requireWhitelistedV3SwapRoutersInstructions

```solidity
function requireWhitelistedV3SwapRoutersInstructions(contract ISharedConfigManager cm, struct IV3Utils.Instructions ins) internal view
```

