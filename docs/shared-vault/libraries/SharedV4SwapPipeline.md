# Solidity API

## SharedV4SwapPipeline

### execute

```solidity
function execute(address swapRouter, address token0, address token1, uint256 amount0, uint256 amount1, struct ISharedV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

### executePancake

```solidity
function executePancake(address swapRouter, address token0, address token1, uint256 amount0, uint256 amount1, struct ISharedPancakeV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

