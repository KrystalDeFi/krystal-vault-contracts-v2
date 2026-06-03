# Solidity API

## SharedV4SwapPipeline

### Swap

_Protocol-neutral swap descriptor. `ISharedV4Utils.SwapParams` and
     `ISharedPancakeV4Utils.SwapParams` are field-for-field identical; both `execute` and
     `executePancake` normalize their protocol-specific input into this single shape and run the
     exact same pipeline (`_run`). Keeping one implementation means the swap-pipeline trust
     boundary is written and audited in one place instead of two._

```solidity
struct Swap {
  address tokenIn;
  uint256 amountIn;
  address tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### execute

```solidity
function execute(address swapRouter, address token0, address token1, uint256 amount0, uint256 amount1, struct ISharedV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

### executePancake

```solidity
function executePancake(address swapRouter, address token0, address token1, uint256 amount0, uint256 amount1, struct ISharedPancakeV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

