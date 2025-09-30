# Solidity API

## IV3Utils

### execute

```solidity
function execute(address _nfpm, uint256 tokenId, bytes instructions) external
```

Execute instruction by pulling approved NFT instead of direct safeTransferFrom call from owner

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _nfpm | address |  |
| tokenId | uint256 | Token to process |
| instructions | bytes | Instructions to execute |

### SwapAndMintParams

Params for swapAndMint() function

```solidity
struct SwapAndMintParams {
  uint8 protocol;
  address nfpm;
  address token0;
  address token1;
  uint24 fee;
  int24 tickLower;
  int24 tickUpper;
  uint64 protocolFeeX64;
  uint256 amount0;
  uint256 amount1;
  uint256 amount2;
  address recipient;
  uint256 deadline;
  address swapSourceToken;
  uint256 amountIn0;
  uint256 amountOut0Min;
  bytes swapData0;
  uint256 amountIn1;
  uint256 amountOut1Min;
  bytes swapData1;
  uint256 amountAddMin0;
  uint256 amountAddMin1;
}
```

### SwapAndMintResult

```solidity
struct SwapAndMintResult {
  uint256 tokenId;
  uint128 liquidity;
  uint256 added0;
  uint256 added1;
}
```

### swapAndMint

```solidity
function swapAndMint(struct IV3Utils.SwapAndMintParams params) external payable returns (struct IV3Utils.SwapAndMintResult result)
```

Does 1 or 2 swaps from swapSourceToken to token0 and token1 and adds as much as possible liquidity to a
newly minted position.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct IV3Utils.SwapAndMintParams | Swap and mint configuration Newly minted NFT and leftover tokens are returned to recipient |

### SwapAndIncreaseLiquidityParams

Params for swapAndIncreaseLiquidity() function

```solidity
struct SwapAndIncreaseLiquidityParams {
  uint8 protocol;
  address nfpm;
  uint256 tokenId;
  uint256 amount0;
  uint256 amount1;
  uint256 amount2;
  address recipient;
  uint256 deadline;
  address swapSourceToken;
  uint256 amountIn0;
  uint256 amountOut0Min;
  bytes swapData0;
  uint256 amountIn1;
  uint256 amountOut1Min;
  bytes swapData1;
  uint256 amountAddMin0;
  uint256 amountAddMin1;
  uint64 protocolFeeX64;
}
```

### SwapAndIncreaseLiquidityResult

```solidity
struct SwapAndIncreaseLiquidityResult {
  uint128 liquidity;
  uint256 added0;
  uint256 added1;
  uint256 feeAmount0;
  uint256 feeAmount1;
}
```

### swapAndIncreaseLiquidity

```solidity
function swapAndIncreaseLiquidity(struct IV3Utils.SwapAndIncreaseLiquidityParams params) external payable returns (struct IV3Utils.SwapAndIncreaseLiquidityResult result)
```

Does 1 or 2 swaps from swapSourceToken to token0 and token1 and adds as much as possible liquidity to any
existing position (no need to be position owner).

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct IV3Utils.SwapAndIncreaseLiquidityParams | Swap and increase liquidity configuration |

