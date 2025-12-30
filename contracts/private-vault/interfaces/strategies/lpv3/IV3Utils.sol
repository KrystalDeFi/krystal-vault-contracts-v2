// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IV3Utils {
  /// @notice Action which should be executed on provided NFT
  enum WhatToDo {
    CHANGE_RANGE,
    WITHDRAW_AND_COLLECT_AND_SWAP,
    COMPOUND_FEES
  }
  /// @notice Complete description of what should be executed on provided NFT - different fields are used depending on
  /// specified WhatToDo

  struct Instructions {
    // what action to perform on provided Uniswap v3 position
    WhatToDo whatToDo;
    // protocol to provide lp
    uint8 protocol;
    // target token for swaps (if this is address(0) no swaps are executed)
    address targetToken;
    // for removing liquidity slippage
    uint256 amountRemoveMin0;
    uint256 amountRemoveMin1;
    // amountIn0 is used for swap and also as minAmount0 for decreased liquidity + collected fees
    uint256 amountIn0;
    // if token0 needs to be swapped to targetToken - set values
    uint256 amountOut0Min;
    bytes swapData0; // encoded data from 0x api call (address,bytes) - allowanceTarget,data
    // amountIn1 is used for swap and also as minAmount1 for decreased liquidity + collected fees
    uint256 amountIn1;
    // if token1 needs to be swapped to targetToken - set values
    uint256 amountOut1Min;
    bytes swapData1; // encoded data from 0x api call (address,bytes) - allowanceTarget,data
    // for creating new positions with CHANGE_RANGE
    int24 tickLower;
    int24 tickUpper;
    bool compoundFees;
    // remove liquidity amount for COMPOUND_FEES (in this case should be probably 0) / CHANGE_RANGE /
    // WITHDRAW_AND_COLLECT_AND_SWAP
    uint128 liquidity;
    // for adding liquidity slippage
    uint256 amountAddMin0;
    uint256 amountAddMin1;
    // for all uniswap deadlineable functions
    uint256 deadline;
    // left over tokens will be sent to this address
    address recipient;
    // if tokenIn or tokenOut is WETH - unwrap
    bool unwrap;
    // protocol fees
    uint64 liquidityFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }
  /// @notice Execute instruction by pulling approved NFT instead of direct safeTransferFrom call from owner
  /// @param tokenId Token to process
  /// @param instructions Instructions to execute

  function execute(address _nfpm, uint256 tokenId, bytes calldata instructions) external;

  struct SwapAndMintResult {
    uint256 tokenId;
    uint128 liquidity;
    uint256 added0;
    uint256 added1;
  }

  struct SwapAndMintParams {
    uint8 protocol;
    address nfpm;
    address token0;
    address token1;
    uint24 fee;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint64 protocolFeeX64;
    uint64 gasFeeX64;
    // how much is provided of token0 and token1
    uint256 amount0;
    uint256 amount1;
    uint256 amount2;
    address recipient; // recipient of tokens
    uint256 deadline;
    // source token for swaps (maybe either address(0), token0, token1 or another token)
    // if swapSourceToken is another token than token0 or token1 -> amountIn0 + amountIn1 of swapSourceToken are
    // expected to be available
    address swapSourceToken;
    // if swapSourceToken needs to be swapped to token0 - set values
    uint256 amountIn0;
    uint256 amountOut0Min;
    bytes swapData0;
    // if swapSourceToken needs to be swapped to token1 - set values
    uint256 amountIn1;
    uint256 amountOut1Min;
    bytes swapData1;
    // min amount to be added after swap
    uint256 amountAddMin0;
    uint256 amountAddMin1;
    address poolDeployer; // only for algebra integral
  }

  /// @notice Does 1 or 2 swaps from swapSourceToken to token0 and token1 and adds as much as possible liquidity to a
  /// newly minted position.
  /// @param params Swap and mint configuration
  /// Newly minted NFT and leftover tokens are returned to recipient
  function swapAndMint(SwapAndMintParams calldata params) external payable returns (SwapAndMintResult memory result);

  struct SwapAndIncreaseLiquidityResult {
    uint128 liquidity;
    uint256 added0;
    uint256 added1;
    uint256 feeAmount0;
    uint256 feeAmount1;
  }
  /// @notice Params for swapAndIncreaseLiquidity() function

  /// @notice Params for swapAndIncreaseLiquidity() function
  struct SwapAndIncreaseLiquidityParams {
    uint8 protocol;
    address nfpm;
    uint256 tokenId;
    // how much is provided of token0 and token1
    uint256 amount0;
    uint256 amount1;
    uint256 amount2;
    address recipient; // recipient of leftover tokens
    uint256 deadline;
    // source token for swaps (maybe either address(0), token0, token1 or another token)
    // if swapSourceToken is another token than token0 or token1 -> amountIn0 + amountIn1 of swapSourceToken are
    // expected to be available
    address swapSourceToken;
    // if swapSourceToken needs to be swapped to token0 - set values
    uint256 amountIn0;
    uint256 amountOut0Min;
    bytes swapData0;
    // if swapSourceToken needs to be swapped to token1 - set values
    uint256 amountIn1;
    uint256 amountOut1Min;
    bytes swapData1;
    // min amount to be added after swap
    uint256 amountAddMin0;
    uint256 amountAddMin1;
    uint64 protocolFeeX64;
    uint64 gasFeeX64;
  }

  /// @notice Does 1 or 2 swaps from swapSourceToken to token0 and token1 and adds as much as possible liquidity to any
  /// existing position (no need to be position owner).
  /// @param params Swap and increase liquidity configuration
  // Sends any leftover tokens to recipient.
  function swapAndIncreaseLiquidity(SwapAndIncreaseLiquidityParams calldata params)
    external
    payable
    returns (SwapAndIncreaseLiquidityResult memory result);
}
