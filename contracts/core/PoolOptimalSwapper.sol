// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { OptimalSwap, V3PoolCallee } from "../libraries/OptimalSwap.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../interfaces/core/IOptimalSwapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@pancakeswap/v3-core/contracts/interfaces/callback/IPancakeV3SwapCallback.sol";

/// @title PoolOptimalSwapper
contract PoolOptimalSwapper is IOptimalSwapper, IUniswapV3SwapCallback, IPancakeV3SwapCallback {
  using SafeERC20 for IERC20;

  uint160 internal constant MAX_SQRT_RATIO_LESS_ONE =
    1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1;
  uint160 internal constant XOR_SQRT_RATIO =
    (4_295_128_739 + 1) ^ (1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1);

  address private currentPool;

  /// @notice Callback function required by Uniswap V3 to finalize swaps
  /// @param amount0Delta The change in token0 balance
  /// @param amount1Delta The change in token1 balance
  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
    require(msg.sender == currentPool, "Incorrect pool");

    IERC20 token0 = IERC20(IUniswapV3Pool(currentPool).token0());
    IERC20 token1 = IERC20(IUniswapV3Pool(currentPool).token1());

    if (amount0Delta > 0) token0.safeTransfer(msg.sender, uint256(amount0Delta));
    else if (amount1Delta > 0) token1.safeTransfer(msg.sender, uint256(amount1Delta));
  }

  /// @notice Callback function required by Pancake V3 to finalize swaps
  /// @param amount0Delta The change in token0 balance
  /// @param amount1Delta The change in token1 balance
  function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
    require(msg.sender == currentPool, "Incorrect pool");

    IERC20 token0 = IERC20(IUniswapV3Pool(currentPool).token0());
    IERC20 token1 = IERC20(IUniswapV3Pool(currentPool).token1());

    if (amount0Delta > 0) token0.safeTransfer(msg.sender, uint256(amount0Delta));
    else if (amount1Delta > 0) token1.safeTransfer(msg.sender, uint256(amount1Delta));
  }

  /// @dev Make a direct `exactIn` pool swap
  /// @param pool The address of the Uniswap V3 pool
  /// @param amountIn The amount of token to be swapped
  /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
  /// @return amountOut The amount of token received after swap
  /// @return amountInUsed The amount of token used for swap
  function _poolSwap(address pool, uint256 amountIn, bool zeroForOne)
    internal
    returns (uint256 amountOut, uint256 amountInUsed)
  {
    if (amountIn != 0) {
      currentPool = pool;
      uint160 sqrtPriceLimitX96;
      // Equivalent to `sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1`
      assembly {
        sqrtPriceLimitX96 := xor(MAX_SQRT_RATIO_LESS_ONE, mul(XOR_SQRT_RATIO, zeroForOne))
      }
      (int256 amount0Delta, int256 amount1Delta) =
        V3PoolCallee.wrap(pool).swap(address(this), zeroForOne, int256(amountIn), sqrtPriceLimitX96, "");

      unchecked {
        amountOut = zeroForOne ? uint256(-amount1Delta) : uint256(-amount0Delta);
        amountInUsed = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
      }
    }
  }

  /// @notice Swap tokens in a Uniswap V3 pool
  /// @param params The parameters for the optimal swap
  /// @return amount0 The amount of token0 received after swap
  /// @return amount1 The amount of token1 received after swap
  function optimalSwap(OptimalSwapParams calldata params) external override returns (uint256 amount0, uint256 amount1) {
    IERC20 token0 = IERC20(IUniswapV3Pool(params.pool).token0());
    IERC20 token1 = IERC20(IUniswapV3Pool(params.pool).token1());

    if (params.amount0Desired > 0) token0.safeTransferFrom(msg.sender, address(this), params.amount0Desired);
    if (params.amount1Desired > 0) token1.safeTransferFrom(msg.sender, address(this), params.amount1Desired);

    (uint256 amountIn,, bool zeroForOne,) = OptimalSwap.getOptimalSwap(
      V3PoolCallee.wrap(params.pool), params.tickLower, params.tickUpper, params.amount0Desired, params.amount1Desired
    );

    (uint256 amountOut, uint256 amountInUsed) = _poolSwap(params.pool, amountIn, zeroForOne);

    // balance0 = balance0 + zeroForOne ? - amountIn : amountOut
    // balance1 = balance1 + zeroForOne ? amountOut : - amountIn
    if (zeroForOne) {
      amount0 = params.amount0Desired - amountInUsed;
      amount1 = params.amount1Desired + amountOut;
    } else {
      amount0 = params.amount0Desired + amountOut;
      amount1 = params.amount1Desired - amountInUsed;
    }

    if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
    if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
  }

  /// @notice Get the optimal swap amounts for a given pool
  /// @param pool The address of the Uniswap V3 pool
  /// @param amount0Desired The desired amount of token0
  /// @param amount1Desired The desired amount of token1
  /// @param tickLower The lower tick of the pool
  /// @param tickUpper The upper tick of the pool
  /// @return amount0 The optimal amount of token0 to swap
  /// @return amount1 The optimal amount of token1 to swap
  function getOptimalSwapAmounts(
    address pool,
    uint256 amount0Desired,
    uint256 amount1Desired,
    int24 tickLower,
    int24 tickUpper,
    bytes calldata
  ) external view returns (uint256 amount0, uint256 amount1) {
    (uint256 amountIn, uint256 amountOut, bool zeroForOne,) =
      OptimalSwap.getOptimalSwap(V3PoolCallee.wrap(pool), tickLower, tickUpper, amount0Desired, amount1Desired);

    // balance0 = balance0 + zeroForOne ? - amountIn : amountOut
    // balance1 = balance1 + zeroForOne ? amountOut : - amountIn
    if (zeroForOne) {
      amount0 = amount0Desired - amountIn;
      amount1 = amount1Desired + amountOut;
    } else {
      amount0 = amount0Desired + amountOut;
      amount1 = amount1Desired - amountIn;
    }
  }

  /// @notice Swap exactIn tokens through an UniswapV3Pool
  /// @param pool The address of the Uniswap V3 pool
  /// @param amountIn The amount of token to be swapped
  /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
  /// @param amountOutMin The minimum amount of token to receive after swap
  /// @return amountOut The amount of token received after swap
  /// @return amountInUsed The amount of token used for swap
  function poolSwap(address pool, uint256 amountIn, bool zeroForOne, uint256 amountOutMin, bytes calldata)
    external
    override
    returns (uint256 amountOut, uint256 amountInUsed)
  {
    IERC20 token0 = IERC20(IUniswapV3Pool(pool).token0());
    IERC20 token1 = IERC20(IUniswapV3Pool(pool).token1());

    IERC20 inputToken = zeroForOne ? token0 : token1;
    IERC20 outputToken = zeroForOne ? token1 : token0;

    if (amountIn > 0) inputToken.safeTransferFrom(msg.sender, address(this), amountIn);

    (amountOut, amountInUsed) = _poolSwap(pool, amountIn, zeroForOne);
    require(amountOut >= amountOutMin, "Insufficient output amount");

    if (amountOut > 0) outputToken.safeTransfer(msg.sender, amountOut);
    if (amountIn > amountInUsed) inputToken.safeTransfer(msg.sender, amountIn - amountInUsed);
  }
}
