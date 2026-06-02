// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ISharedPancakeV4Utils } from "../interfaces/ISharedPancakeV4Utils.sol";
import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedV4Utils } from "../interfaces/ISharedV4Utils.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";

library SharedV4SwapPipeline {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  function execute(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;

    if (swapParams.length > 0) {
      require(
        ISharedVault(address(this)).configManager().isWhitelistedSwapRouter(swapRouter),
        ISharedCommon.InvalidSwapRouter(swapRouter)
      );
    }

    address[] memory intTokens = new address[](swapParams.length);
    uint256[] memory intBalances = new uint256[](swapParams.length);
    uint256 intCount;

    for (uint256 i; i < swapParams.length;) {
      ISharedV4Utils.SwapParams memory swapParam = swapParams[i];
      require(
        _isV4SwapInputAllowed(token0, token1, swapParam.tokenIn, swapParams, i)
          && _isV4SwapOutputAllowed(token0, token1, swapParam.tokenOut, swapParams, i),
        ISharedStrategy.InvalidPoolTokens()
      );

      uint256 amountIn = swapParam.amountIn;
      uint256 inIdx;
      bool inIsIntermediate;
      if (swapParam.tokenIn == token0) {
        if (amountIn == 0) amountIn = total0;
        require(amountIn <= total0, ISharedCommon.InvalidAmount());
      } else if (swapParam.tokenIn == token1) {
        if (amountIn == 0) amountIn = total1;
        require(amountIn <= total1, ISharedCommon.InvalidAmount());
      } else {
        inIsIntermediate = true;
        inIdx = _findIntermediate(intTokens, intCount, swapParam.tokenIn);
        uint256 tracked = inIdx < intCount ? intBalances[inIdx] : 0;
        if (amountIn == 0) amountIn = tracked;
        require(amountIn <= tracked, ISharedCommon.InvalidAmount());
      }

      if (amountIn == 0) {
        require(swapParam.amountOutMin == 0, ISharedCommon.InsufficientOutput());
        unchecked {
          i++;
        }
        continue;
      }

      (uint256 amountInDelta, uint256 amountOutDelta) = _swapV4(
        swapRouter, swapParam.tokenIn, swapParam.tokenOut, amountIn, swapParam.amountOutMin, swapParam.swapData, i
      );

      if (inIsIntermediate) intBalances[inIdx] -= amountInDelta;
      else if (swapParam.tokenIn == token0) total0 -= amountInDelta;
      else total1 -= amountInDelta;

      if (swapParam.tokenOut == token0) {
        total0 += amountOutDelta;
      } else if (swapParam.tokenOut == token1) {
        total1 += amountOutDelta;
      } else {
        uint256 outIdx = _findIntermediate(intTokens, intCount, swapParam.tokenOut);
        if (outIdx == intCount) {
          intTokens[intCount] = swapParam.tokenOut;
          unchecked {
            intCount++;
          }
        }
        intBalances[outIdx] += amountOutDelta;
      }

      unchecked {
        i++;
      }
    }

    for (uint256 j; j < intCount;) {
      require(intBalances[j] == 0, ISharedCommon.InvalidAmount());
      unchecked {
        j++;
      }
    }
  }

  function executePancake(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;

    if (swapParams.length > 0) {
      require(
        ISharedVault(address(this)).configManager().isWhitelistedSwapRouter(swapRouter),
        ISharedCommon.InvalidSwapRouter(swapRouter)
      );
    }

    address[] memory intTokens = new address[](swapParams.length);
    uint256[] memory intBalances = new uint256[](swapParams.length);
    uint256 intCount;

    for (uint256 i; i < swapParams.length;) {
      ISharedPancakeV4Utils.SwapParams memory swapParam = swapParams[i];
      require(
        _isPancakeSwapInputAllowed(token0, token1, swapParam.tokenIn, swapParams, i)
          && _isPancakeSwapOutputAllowed(token0, token1, swapParam.tokenOut, swapParams, i),
        ISharedStrategy.InvalidPoolTokens()
      );

      uint256 amountIn = swapParam.amountIn;
      uint256 inIdx;
      bool inIsIntermediate;
      if (swapParam.tokenIn == token0) {
        if (amountIn == 0) amountIn = total0;
        require(amountIn <= total0, ISharedCommon.InvalidAmount());
      } else if (swapParam.tokenIn == token1) {
        if (amountIn == 0) amountIn = total1;
        require(amountIn <= total1, ISharedCommon.InvalidAmount());
      } else {
        inIsIntermediate = true;
        inIdx = _findIntermediate(intTokens, intCount, swapParam.tokenIn);
        uint256 tracked = inIdx < intCount ? intBalances[inIdx] : 0;
        if (amountIn == 0) amountIn = tracked;
        require(amountIn <= tracked, ISharedCommon.InvalidAmount());
      }

      if (amountIn == 0) {
        require(swapParam.amountOutMin == 0, ISharedCommon.InsufficientOutput());
        unchecked {
          i++;
        }
        continue;
      }

      (uint256 amountInDelta, uint256 amountOutDelta) = _swapV4(
        swapRouter, swapParam.tokenIn, swapParam.tokenOut, amountIn, swapParam.amountOutMin, swapParam.swapData, i
      );

      if (inIsIntermediate) intBalances[inIdx] -= amountInDelta;
      else if (swapParam.tokenIn == token0) total0 -= amountInDelta;
      else total1 -= amountInDelta;

      if (swapParam.tokenOut == token0) {
        total0 += amountOutDelta;
      } else if (swapParam.tokenOut == token1) {
        total1 += amountOutDelta;
      } else {
        uint256 outIdx = _findIntermediate(intTokens, intCount, swapParam.tokenOut);
        if (outIdx == intCount) {
          intTokens[intCount] = swapParam.tokenOut;
          unchecked {
            intCount++;
          }
        }
        intBalances[outIdx] += amountOutDelta;
      }

      unchecked {
        i++;
      }
    }

    for (uint256 j; j < intCount;) {
      require(intBalances[j] == 0, ISharedCommon.InvalidAmount());
      unchecked {
        j++;
      }
    }
  }

  function _findIntermediate(address[] memory intTokens, uint256 intCount, address token)
    private
    pure
    returns (uint256 idx)
  {
    for (uint256 i; i < intCount;) {
      if (intTokens[i] == token) return i;
      unchecked {
        i++;
      }
    }
    return intCount;
  }

  function _isV4SwapInputAllowed(
    address token0,
    address token1,
    address tokenIn,
    ISharedV4Utils.SwapParams[] memory swapParams,
    uint256 index
  ) private pure returns (bool) {
    if (tokenIn == token0 || tokenIn == token1) return true;
    for (uint256 i; i < index;) {
      if (swapParams[i].tokenOut == tokenIn) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _isV4SwapOutputAllowed(
    address token0,
    address token1,
    address tokenOut,
    ISharedV4Utils.SwapParams[] memory swapParams,
    uint256 index
  ) private pure returns (bool) {
    if (tokenOut == token0 || tokenOut == token1) return true;
    if (tokenOut == address(0)) return false;
    for (uint256 i = index + 1; i < swapParams.length;) {
      if (swapParams[i].tokenIn == tokenOut) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _isPancakeSwapInputAllowed(
    address token0,
    address token1,
    address tokenIn,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams,
    uint256 index
  ) private pure returns (bool) {
    if (tokenIn == token0 || tokenIn == token1) return true;
    for (uint256 i; i < index;) {
      if (swapParams[i].tokenOut == tokenIn) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _isPancakeSwapOutputAllowed(
    address token0,
    address token1,
    address tokenOut,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams,
    uint256 index
  ) private pure returns (bool) {
    if (tokenOut == token0 || tokenOut == token1) return true;
    if (tokenOut == address(0)) return false;
    for (uint256 i = index + 1; i < swapParams.length;) {
      if (swapParams[i].tokenIn == tokenOut) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _swapV4(
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory swapData,
    uint256 swapIndex
  ) private returns (uint256 amountInDelta, uint256 amountOutDelta) {
    if (amountIn == 0 || swapData.length == 0 || tokenOut == address(0)) {
      require(amountOutMin == 0, ISharedCommon.InsufficientOutput());
      return (0, 0);
    }
    require(tokenIn != tokenOut, ISharedCommon.InvalidOperation());

    uint256 balanceInBefore = IERC20(tokenIn).balanceOf(address(this));
    uint256 balanceOutBefore = IERC20(tokenOut).balanceOf(address(this));
    IERC20(tokenIn).safeResetAndApprove(swapRouter, amountIn);
    (bool success,) = swapRouter.call(swapData);
    if (!success) revert ISharedCommon.SwapFailed(swapIndex);
    IERC20(tokenIn).safeApprove(swapRouter, 0);
    uint256 balanceInAfter = IERC20(tokenIn).balanceOf(address(this));
    uint256 balanceOutAfter = IERC20(tokenOut).balanceOf(address(this));

    amountInDelta = balanceInBefore - balanceInAfter;
    amountOutDelta = balanceOutAfter - balanceOutBefore;
    require(amountOutDelta >= amountOutMin, ISharedCommon.InsufficientOutput());
  }
}
