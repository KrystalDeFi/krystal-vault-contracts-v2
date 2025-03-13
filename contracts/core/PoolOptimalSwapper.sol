// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.28;

import { OptimalSwap, V3PoolCallee } from "../libraries/OptimalSwap.sol";
import { TernaryLib } from "@aperture_finance/uni-v3-lib/src/TernaryLib.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../interfaces/core/IOptimalSwapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract PoolOptimalSwapper is IOptimalSwapper, IUniswapV3SwapCallback {
  using TernaryLib for bool;
  using SafeERC20 for IERC20;

  uint160 internal constant MAX_SQRT_RATIO_LESS_ONE =
    1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1;
  uint160 internal constant XOR_SQRT_RATIO =
    (4_295_128_739 + 1) ^ (1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1);

  address private currentPool;
  /// @notice Callback function required by Uniswap V3 to finalize swaps

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
    require(msg.sender == currentPool, "Incorrect pool");

    if (amount0Delta > 0) {
      IERC20(IUniswapV3Pool(currentPool).token0()).transfer(msg.sender, uint256(amount0Delta));
    } else if (amount1Delta > 0) {
      IERC20(IUniswapV3Pool(currentPool).token1()).transfer(msg.sender, uint256(amount1Delta));
    }
  }

  /// @dev Make a direct `exactIn` pool swap
  /// @param amountIn The amount of token to be swapped
  /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to
  /// token0
  /// @return amountOut The amount of token received after swap
  function _poolSwap(
    address pool,
    uint256 amountIn,
    bool zeroForOne
  ) internal returns (uint256 amountOut, uint256 amountInUsed) {
    if (amountIn != 0) {
      currentPool = pool;
      uint160 sqrtPriceLimitX96;
      // Equivalent to `sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1`
      assembly {
        sqrtPriceLimitX96 := xor(MAX_SQRT_RATIO_LESS_ONE, mul(XOR_SQRT_RATIO, zeroForOne))
      }
      (int256 amount0Delta, int256 amount1Delta) = V3PoolCallee.wrap(pool).swap(
        address(this),
        zeroForOne,
        int256(amountIn),
        sqrtPriceLimitX96,
        ""
      );
      unchecked {
        amountOut = 0 - zeroForOne.ternary(uint256(amount1Delta), uint256(amount0Delta));
        amountInUsed = zeroForOne.ternary(uint256(amount0Delta), uint256(amount1Delta));
      }
    }
  }

  /// @notice Swap tokens in a Uniswap V3 pool
  /// @param params The parameters for the optimal swap
  function optimalSwap(OptimalSwapParams memory params) external override returns (uint256 amount0, uint256 amount1) {
    IERC20 token0 = IERC20(IUniswapV3Pool(params.pool).token0());
    IERC20 token1 = IERC20(IUniswapV3Pool(params.pool).token1());
    token0.transferFrom(msg.sender, address(this), params.amount0Desired);
    token1.transferFrom(msg.sender, address(this), params.amount1Desired);

    uint256 amountIn;
    uint256 amountOut;
    bool zeroForOne;
    {
      (amountIn, , zeroForOne, ) = OptimalSwap.getOptimalSwap(
        V3PoolCallee.wrap(params.pool),
        params.tickLower,
        params.tickUpper,
        params.amount0Desired,
        params.amount1Desired
      );
      (amountOut, amountIn) = _poolSwap(params.pool, amountIn, zeroForOne);
    }

    // balance0 = balance0 + zeroForOne ? - amountIn : amountOut
    // balance1 = balance1 + zeroForOne ? amountOut : - amountIn
    if (zeroForOne) {
      amount0 = params.amount0Desired - amountIn;
      amount1 = params.amount1Desired + amountOut;
    } else {
      amount0 = params.amount0Desired + amountOut;
      amount1 = params.amount1Desired - amountIn;
    }

    token0.transfer(msg.sender, amount0);
    token1.transfer(msg.sender, amount1);
  }

  function getOptimalSwapAmounts(
    address pool,
    uint256 amount0Desired,
    uint256 amount1Desired,
    int24 tickLower,
    int24 tickUpper,
    bytes calldata
  ) external view returns (uint256 amount0, uint256 amount1) {
    (uint256 amountIn, uint256 amountOut, bool zeroForOne, ) = OptimalSwap.getOptimalSwap(
      V3PoolCallee.wrap(pool),
      tickLower,
      tickUpper,
      amount0Desired,
      amount1Desired
    );

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
  /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to
  /// token0
  /// @param amountOutMin The minimum amount of token to receive after swap
  function poolSwap(
    address pool,
    uint256 amountIn,
    bool zeroForOne,
    uint256 amountOutMin,
    bytes calldata
  ) external override returns (uint256 amountOut, uint256 amountInUsed) {
    IERC20 token0 = IERC20(IUniswapV3Pool(pool).token0());
    IERC20 token1 = IERC20(IUniswapV3Pool(pool).token1());
    if (zeroForOne) token0.transferFrom(msg.sender, address(this), amountIn);
    else token1.transferFrom(msg.sender, address(this), amountIn);

    (amountOut, amountInUsed) = _poolSwap(pool, amountIn, zeroForOne);
    require(amountOut >= amountOutMin, "Insufficient output amount");
    IERC20(zeroForOne.ternary(address(token1), address(token0))).transfer(msg.sender, amountOut);
    if (amountIn > amountInUsed) {
      IERC20(zeroForOne.ternary(address(token0), address(token1))).transfer(msg.sender, amountIn - amountInUsed);
    }
  }
}
