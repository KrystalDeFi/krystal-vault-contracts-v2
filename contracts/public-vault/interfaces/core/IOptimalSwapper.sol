// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IOptimalSwapper {
  struct OptimalSwapParams {
    address pool;
    uint256 amount0Desired;
    uint256 amount1Desired;
    int24 tickLower;
    int24 tickUpper;
    bytes data;
  }

  function optimalSwap(OptimalSwapParams calldata params)
    external
    returns (uint256 amount0Result, uint256 amount1Result);

  function getOptimalSwapAmounts(
    address pool,
    uint256 amount0Desired,
    uint256 amount1Desired,
    int24 tickLower,
    int24 tickUpper,
    bytes calldata data
  ) external view returns (uint256 amount0, uint256 amount1);

  function poolSwap(address pool, uint256 amountIn, bool zeroToOne, uint256 amountOutMin, bytes calldata data)
    external
    returns (uint256 amountOut, uint256 amountInUsed);
}
