# Solidity API

## ISharedPancakeV4Utils

### Swap

```solidity
event Swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
```

### SwapAndMint

```solidity
event SwapAndMint(address posm, uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1)
```

_The amount fields on SwapAndMint / SwapAndIncrease / AdjustRange / CompoundFees report the
     amounts CONSUMED by the realized liquidity, quoted at the execution price (v4utils parity).
     For imbalanced or out-of-range adds the non-limiting side's remainder stays idle in the
     vault and is NOT reported._

### SwapAndIncrease

```solidity
event SwapAndIncrease(address posm, uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1)
```

### DecreaseAndSwap

```solidity
event DecreaseAndSwap(address posm, uint256 tokenId, uint128 liquidity, Currency token, uint256 amount)
```

_`token`/`amount` report `swapDestToken` and this operation's post-swap proceeds in it.
     For a pool-token dest that is the post-swap total; for a non-pool VAULT-token dest it is
     the terminal swap output left idle by the pipeline; otherwise 0 (no allowance, nothing
     can flow there). Unlike v4utils nothing is swept — proceeds stay idle in the vault._

### AdjustRange

```solidity
event AdjustRange(address posm, uint256 tokenId, uint256 newTokenId, uint256 newLiquidity, uint256 token0Added, uint256 token1Added)
```

### CompoundFees

```solidity
event CompoundFees(address posm, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
```

### UtilActions

```solidity
enum UtilActions {
  ADJUST_RANGE,
  DECREASE_AND_SWAP,
  COMPOUND
}
```

### Instructions

```solidity
struct Instructions {
  enum ISharedPancakeV4Utils.UtilActions action;
  bytes params;
}
```

### DecreaseLiquidityParams

```solidity
struct DecreaseLiquidityParams {
  uint128 liquidity;
  uint256 deadline;
  uint256 amount0Min;
  uint256 amount1Min;
  bytes hookData;
}
```

### MintParams

```solidity
struct MintParams {
  int24 tickLower;
  int24 tickUpper;
  uint256 minLiquidity;
  bytes hookData;
  uint256 deadline;
}
```

### IncreaseLiquidityParams

```solidity
struct IncreaseLiquidityParams {
  uint256 minLiquidity;
  bytes hookData;
  uint256 deadline;
}
```

### SwapParams

_SharedV4SwapPipeline forwards `amountIn` to signature verification verbatim — the digest
     binds this exact amount, never an on-chain computed balance — and the tracked total only
     needs to cover it (the backend folds withdraw-liquidity slippage into the signed amount;
     the un-swapped remainder stays in the totals). `amountIn == 0` means "no swap for this hop"
     (`amountOutMin` must be 0); it is NOT resolved to the available balance. `amountOutMin` is
     signer-controlled; signers must apply their own route/oracle slippage policy._

```solidity
struct SwapParams {
  Currency tokenIn;
  uint256 amountIn;
  Currency tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### InputTokenParams

```solidity
struct InputTokenParams {
  Currency token;
  uint256 amount;
}
```

### SwapAndMintParams

```solidity
struct SwapAndMintParams {
  address posm;
  struct PoolKey poolKey;
  struct ISharedPancakeV4Utils.MintParams mintParams;
  struct ISharedPancakeV4Utils.SwapParams[] swapParams;
  struct ISharedPancakeV4Utils.InputTokenParams[] inputTokens;
  Currency[] sweepTokens;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
}
```

### SwapAndIncreaseParams

```solidity
struct SwapAndIncreaseParams {
  address posm;
  uint256 tokenId;
  struct ISharedPancakeV4Utils.IncreaseLiquidityParams increaseParams;
  struct ISharedPancakeV4Utils.SwapParams[] swapParams;
  struct ISharedPancakeV4Utils.InputTokenParams[] inputTokens;
  Currency[] sweepTokens;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
}
```

### DecreaseAndSwapParams

```solidity
struct DecreaseAndSwapParams {
  struct ISharedPancakeV4Utils.DecreaseLiquidityParams decreaseParams;
  struct ISharedPancakeV4Utils.SwapParams[] swapParams;
  Currency swapDestToken;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
}
```

### AdjustRangeParams

```solidity
struct AdjustRangeParams {
  bytes collectFeesHookData;
  struct ISharedPancakeV4Utils.SwapParams[] swapParams;
  struct ISharedPancakeV4Utils.MintParams mintParams;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
  bool compoundFees;
}
```

### CompoundFeesParams

```solidity
struct CompoundFeesParams {
  bytes collectFeesHookData;
  struct ISharedPancakeV4Utils.SwapParams[] swapParams;
  struct ISharedPancakeV4Utils.IncreaseLiquidityParams increaseParams;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
}
```

### swapAndMint

```solidity
function swapAndMint(struct ISharedPancakeV4Utils.SwapAndMintParams params) external payable
```

### swapAndIncrease

```solidity
function swapAndIncrease(struct ISharedPancakeV4Utils.SwapAndIncreaseParams params) external
```

### execute

```solidity
function execute(address posm, uint256 tokenId, struct ISharedPancakeV4Utils.Instructions instructions) external
```

