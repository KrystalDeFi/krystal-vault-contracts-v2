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

### requireNoLiquidityHookCL

```solidity
function requireNoLiquidityHookCL(bytes32 parameters) internal pure
```

PancakeSwap Infinity: reject pools whose hook intercepts liquidity ADD or REMOVAL.

_The CL PoolManager only routes an add (`liquidityDelta > 0`) or a remove
     (`liquidityDelta <= 0`, including the zero-liquidity fee-sync collect) through the hook
     when the corresponding before/after{Add,Remove}Liquidity bit is registered in
     `PoolKey.parameters`. If none are registered, the hook never runs on the permissionless
     deposit/withdraw/adjust liquidity paths, so empty hookData is provably safe — an
     add-hook could otherwise freeze deposits, a remove-hook could freeze withdrawals. Common
     swap-side hooks (dynamic fees, fee discounts, oracles, MEV) register only swap/initialize
     callbacks and pass._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| parameters | bytes32 | The `PoolKey.parameters` bitmap; offsets 2/3 add, 4/5 remove. |

### requireNoLiquidityHookV4

```solidity
function requireNoLiquidityHookV4(contract IHooks hooks) internal pure
```

Uniswap V4: reject pools whose hook intercepts liquidity ADD or REMOVAL.

_V4 encodes hook permissions in the hook address bits. A hook without any
     before/after{Add,Remove}Liquidity permission is never invoked on the permissionless
     deposit/withdraw paths, so empty hookData is provably safe. `address(0)` (hookless) has
     no permission bits and passes; swap-side hooks (e.g. dynamic fees, FairFlow) pass too._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hooks | contract IHooks | The pool's hook; permission bits live in the hook address. |

