# Solidity API

## ISharedPancakeV4Utils

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

```solidity
struct SwapParams {
  address tokenIn;
  uint256 amountIn;
  address tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### InputTokenParams

```solidity
struct InputTokenParams {
  address token;
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
function swapAndMint(struct ISharedPancakeV4Utils.SwapAndMintParams params) external
```

_Not `payable`: `SharedPancakeV4Strategy._execute` enforces `ethValue == 0` and
     `_validateVaultToken` rejects `address(0)`, so native-currency pools are not supported._

### swapAndIncrease

```solidity
function swapAndIncrease(struct ISharedPancakeV4Utils.SwapAndIncreaseParams params) external
```

### execute

```solidity
function execute(address posm, uint256 tokenId, struct ISharedPancakeV4Utils.Instructions instructions) external
```

