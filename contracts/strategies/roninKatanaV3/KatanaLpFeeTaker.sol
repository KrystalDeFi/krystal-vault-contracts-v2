// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { PoolOptimalSwapper } from "../../core/PoolOptimalSwapper.sol";

import { OptimalSwap, V3PoolCallee } from "../../libraries/OptimalSwap.sol";

import { ILpFeeTaker } from "../../interfaces/strategies/ILpFeeTaker.sol";
import { ILpValidator } from "../../interfaces/strategies/ILpValidator.sol";
import { IAggregateRouter } from "../../interfaces/strategies/roninKatanaV3/IAggregateRouter.sol";

contract KatanaLpFeeTaker is ILpFeeTaker {
  using SafeERC20 for IERC20;

  uint256 internal constant Q64 = 0x10000000000000000;
  uint160 internal constant MAX_SQRT_RATIO_LESS_ONE =
    1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1;
  uint160 internal constant XOR_SQRT_RATIO =
    (4_295_128_739 + 1) ^ (1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1);

  address private currentPool;
  IAggregateRouter public router;

  constructor(address _router) {
    router = IAggregateRouter(_router);
  }

  function takeFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    FeeConfig memory feeConfig,
    address principalToken,
    address pool,
    address validator
  ) external returns (uint256 fee0, uint256 fee1) {
    uint256 principalPlatformFee;
    uint256 principalVaultOwnerFee;
    uint256 principalGasFee;
    uint256 leftOverPlatformFee;
    uint256 leftOverVaultOwnerFee;
    uint256 leftOverGasFee;

    if (amount0 > 0) {
      (fee0, principalPlatformFee, principalVaultOwnerFee, principalGasFee) = _takeFee(amount0, feeConfig);
      if (fee0 > 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), fee0);
    }
    if (amount1 > 0) {
      (fee1, leftOverPlatformFee, leftOverVaultOwnerFee, leftOverGasFee) = _takeFee(amount1, feeConfig);
      if (fee1 > 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), fee1);
    }

    bool token0IsPrincipal = token0 == principalToken;
    address leftOverToken = token1;
    if (!token0IsPrincipal) {
      leftOverToken = token0;
      (principalPlatformFee, leftOverPlatformFee) = (leftOverPlatformFee, principalPlatformFee);
      (principalVaultOwnerFee, leftOverVaultOwnerFee) = (leftOverVaultOwnerFee, principalVaultOwnerFee);
      (principalGasFee, leftOverGasFee) = (leftOverGasFee, principalGasFee);
    }
    {
      // swap leftOver to principal
      uint256 totalLeftOver = leftOverGasFee + leftOverPlatformFee + leftOverVaultOwnerFee;
      if (totalLeftOver > 0) {
        (uint256 amountOut, uint256 amountIn) = _swapToPrincipal(
          SwapToPrincipalParams({
            pool: pool,
            token: leftOverToken,
            amount: totalLeftOver,
            principalToken: principalToken,
            amountOutMin: 0,
            swapData: ""
          }),
          ILpValidator(validator)
        );
        principalPlatformFee += FullMath.mulDiv(amountOut, leftOverPlatformFee, totalLeftOver);
        principalVaultOwnerFee += FullMath.mulDiv(amountOut, leftOverVaultOwnerFee, totalLeftOver);
        principalGasFee += FullMath.mulDiv(amountOut, leftOverGasFee, totalLeftOver);
        if (amountIn == totalLeftOver) {
          leftOverPlatformFee = 0;
          leftOverVaultOwnerFee = 0;
          leftOverGasFee = 0;
        } else {
          // if the swap is not exactIn, we need to calculate the left over tokens
          leftOverPlatformFee -= FullMath.mulDiv(amountIn, leftOverPlatformFee, totalLeftOver);
          leftOverVaultOwnerFee -= FullMath.mulDiv(amountIn, leftOverVaultOwnerFee, totalLeftOver);
          leftOverGasFee -= FullMath.mulDiv(amountIn, leftOverGasFee, totalLeftOver);
        }
      }
    }
    address recipient;
    recipient = feeConfig.platformFeeRecipient;
    if (principalPlatformFee > 0) {
      IERC20(principalToken).safeTransfer(recipient, principalPlatformFee);
      emit FeeCollected(msg.sender, FeeType.PLATFORM, recipient, principalToken, principalPlatformFee);
    }
    if (leftOverPlatformFee > 0) {
      IERC20(leftOverToken).safeTransfer(recipient, leftOverPlatformFee);
      emit FeeCollected(msg.sender, FeeType.PLATFORM, recipient, leftOverToken, leftOverPlatformFee);
    }

    recipient = feeConfig.vaultOwner;
    if (principalVaultOwnerFee > 0) {
      IERC20(principalToken).safeTransfer(recipient, principalVaultOwnerFee);
      emit FeeCollected(msg.sender, FeeType.OWNER, recipient, principalToken, principalVaultOwnerFee);
    }
    if (leftOverVaultOwnerFee > 0) {
      IERC20(leftOverToken).safeTransfer(recipient, leftOverVaultOwnerFee);
      emit FeeCollected(msg.sender, FeeType.OWNER, recipient, leftOverToken, leftOverVaultOwnerFee);
    }

    recipient = feeConfig.gasFeeRecipient;
    if (principalGasFee > 0) {
      IERC20(principalToken).safeTransfer(recipient, principalGasFee);
      emit FeeCollected(msg.sender, FeeType.GAS, recipient, principalToken, principalGasFee);
    }
    if (leftOverGasFee > 0) {
      IERC20(leftOverToken).safeTransfer(recipient, leftOverGasFee);
      emit FeeCollected(msg.sender, FeeType.GAS, recipient, leftOverToken, leftOverGasFee);
    }
  }

  /// @dev Takes the fee from the amount
  /// @param amount The amount to take the fee
  /// @param feeConfig The fee configuration
  /// @return totalFeeAmount The total fee amount
  function _takeFee(uint256 amount, FeeConfig memory feeConfig)
    internal
    pure
    returns (uint256 totalFeeAmount, uint256 platformFeeAmount, uint256 vaultOwnerFeeAmount, uint256 gasFeeAmount)
  {
    if (feeConfig.platformFeeBasisPoint > 0) {
      platformFeeAmount = (amount * feeConfig.platformFeeBasisPoint) / 10_000;
      if (platformFeeAmount > 0) totalFeeAmount += platformFeeAmount;
    }
    if (feeConfig.vaultOwnerFeeBasisPoint > 0) {
      vaultOwnerFeeAmount = (amount * feeConfig.vaultOwnerFeeBasisPoint) / 10_000;
      if (vaultOwnerFeeAmount > 0) totalFeeAmount += vaultOwnerFeeAmount;
    }
    if (feeConfig.gasFeeX64 > 0) {
      gasFeeAmount = FullMath.mulDiv(amount, feeConfig.gasFeeX64, Q64);
      if (gasFeeAmount > 0) totalFeeAmount += gasFeeAmount;
    }
  }

  /// @notice Swaps the token to the principal token
  /// @param params The parameters for swapping the token
  /// @return amountOut The result amount of principal token
  /// @return amountInUsed The amount of token used
  function _swapToPrincipal(SwapToPrincipalParams memory params, ILpValidator validator)
    internal
    returns (uint256 amountOut, uint256 amountInUsed)
  {
    require(params.token != params.principalToken, "token is already principal");

    if (address(validator) != address(0)) validator.validatePriceSanity(params.pool);

    (amountOut, amountInUsed) = _poolSwap(params.pool, params.amount, params.token < params.principalToken);
    require(amountOut >= params.amountOutMin, "Insufficient output amount");
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
        true // payerIsUser
      );

      router.execute(
        hex"00", // V3_SWAP_EXACT_IN = 0x00
        inputs,
        block.timestamp + 300 // deadline = 5 mins
      );

      uint256 amountInAfter = tokenIn.balanceOf(address(this));
      uint256 amountOutAfter = tokenOut.balanceOf(address(this));

      amountInUsed = amountInBefore - amountInAfter;
      amountOut = amountOutAfter - amountOutBefore;
    }
  }
}
