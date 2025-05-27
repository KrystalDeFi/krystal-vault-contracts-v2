// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { OptimalSwap, V3PoolCallee } from "../../libraries/OptimalSwap.sol";

import "../../interfaces/core/IOptimalSwapper.sol";
import { IAggregateRouter } from "../../interfaces/strategies/roninKatanaV3/IAggregateRouter.sol";

/// @title PoolOptimalSwapper
contract KatanaPoolOptimalSwapper is IOptimalSwapper {
  using SafeERC20 for IERC20;

  error ApproveFailed();

  uint160 internal constant MAX_SQRT_RATIO_LESS_ONE =
    1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1;
  uint160 internal constant XOR_SQRT_RATIO =
    (4_295_128_739 + 1) ^ (1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1);

  address private currentPool;
  IAggregateRouter public router;

  constructor(address _router) {
    router = IAggregateRouter(_router);
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

      IERC20 token0 = IERC20(IUniswapV3Pool(pool).token0());
      IERC20 token1 = IERC20(IUniswapV3Pool(pool).token1());

      IERC20 tokenIn = zeroForOne ? token0 : token1;
      IERC20 tokenOut = zeroForOne ? token1 : token0;
      uint24 fee = IUniswapV3Pool(pool).fee();

      uint256 amountInBefore = tokenIn.balanceOf(address(this));
      uint256 amountOutBefore = tokenOut.balanceOf(address(this));

      tokenIn.safeTransfer(address(router), amountIn);

      bytes[] memory inputs = new bytes[](1);

      // Build pathData for Uniswap V3: [tokenIn, fee, tokenOut]
      bytes memory path = abi.encodePacked(address(tokenIn), fee, address(tokenOut));
      inputs[0] = abi.encode(
        address(this), // recipient
        uint256(amountIn), // amountIn
        0, // amountOutMinimum
        path, // path data
        false // payerIsUser
      );

      router.execute(
        hex"00", // V3_SWAP_EXACT_IN = 0x00
        inputs,
        block.timestamp
      );

      uint256 amountInAfter = tokenIn.balanceOf(address(this));
      uint256 amountOutAfter = tokenOut.balanceOf(address(this));

      amountInUsed = amountInBefore - amountInAfter;
      amountOut = amountOutAfter - amountOutBefore;
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

    token0.safeTransfer(msg.sender, amount0);
    token1.safeTransfer(msg.sender, amount1);
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

    inputToken.safeTransferFrom(msg.sender, address(this), amountIn);

    (amountOut, amountInUsed) = _poolSwap(pool, amountIn, zeroForOne);
    require(amountOut >= amountOutMin, "Insufficient output amount");

    outputToken.safeTransfer(msg.sender, amountOut);
    if (amountIn > amountInUsed) inputToken.safeTransfer(msg.sender, amountIn - amountInUsed);
  }
}
