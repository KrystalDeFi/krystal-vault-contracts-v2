// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedPancakeV4Utils } from "../interfaces/ISharedPancakeV4Utils.sol";
import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedV4Utils } from "../interfaces/ISharedV4Utils.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { SharedSwapDataSignature } from "./SharedSwapDataSignature.sol";
import { Currency as UniCurrency } from "@uniswap/v4-core/src/types/Currency.sol";
import { Currency as PancakeCurrency } from "infinity-core/src/types/Currency.sol";

library SharedV4SwapPipeline {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  /// @dev Protocol-neutral swap descriptor. `ISharedV4Utils.SwapParams` and
  ///      `ISharedPancakeV4Utils.SwapParams` are field-for-field identical; both `execute` and
  ///      `executePancake` normalize their protocol-specific input into this single shape and run the
  ///      exact same pipeline (`_run`). Keeping one implementation means the swap-pipeline trust
  ///      boundary is written and audited in one place instead of two.
  struct Swap {
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
    uint256 amountOutMin;
    bytes swapData;
  }

  function execute(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    return _run(
      swapRouter, token0, token1, amount0, amount1, _normalizeV4(swapParams, ISharedVault(address(this)).weth())
    );
  }

  function executePancake(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    return _run(
      swapRouter, token0, token1, amount0, amount1, _normalizePancake(swapParams, ISharedVault(address(this)).weth())
    );
  }

  /// @dev Copy a V4 swap list into the protocol-neutral `Swap[]` shape (positional 1:1 mapping; the
  ///      `swapData` bytes reference is shared, not deep-copied).
  function _normalizeV4(ISharedV4Utils.SwapParams[] memory swapParams, address weth)
    private
    pure
    returns (Swap[] memory swaps)
  {
    swaps = new Swap[](swapParams.length);
    for (uint256 i; i < swapParams.length;) {
      swaps[i] = Swap(
        _vaultToken(UniCurrency.unwrap(swapParams[i].tokenIn), weth),
        swapParams[i].amountIn,
        _vaultToken(UniCurrency.unwrap(swapParams[i].tokenOut), weth),
        swapParams[i].amountOutMin,
        swapParams[i].swapData
      );
      unchecked {
        i++;
      }
    }
  }

  /// @dev Copy a PancakeV4 swap list into the protocol-neutral `Swap[]` shape (positional 1:1 mapping).
  function _normalizePancake(ISharedPancakeV4Utils.SwapParams[] memory swapParams, address weth)
    private
    pure
    returns (Swap[] memory swaps)
  {
    swaps = new Swap[](swapParams.length);
    for (uint256 i; i < swapParams.length;) {
      swaps[i] = Swap(
        _vaultToken(PancakeCurrency.unwrap(swapParams[i].tokenIn), weth),
        swapParams[i].amountIn,
        _vaultToken(PancakeCurrency.unwrap(swapParams[i].tokenOut), weth),
        swapParams[i].amountOutMin,
        swapParams[i].swapData
      );
      unchecked {
        i++;
      }
    }
  }

  function _vaultToken(address currency, address weth) private pure returns (address token) {
    token = currency == address(0) ? weth : currency;
  }

  /// @dev The single swap-pipeline implementation shared by both protocols. Validates the top-level
  ///      immutable `swapRouter` is whitelisted, then for each hop enforces input/output token
  ///      reachability, draws the input from principal (token0/token1) or a tracked intermediate
  ///      balance, executes the swap, and books the deltas. After the loop every intermediate balance
  ///      must net to zero (no token left stranded).
  ///
  ///      Trust boundary: `swapData` is opaque calldata executed only against `swapRouter`. This
  ///      pipeline does not parse or re-check any downstream router/adapter target embedded inside
  ///      that calldata; the config-manager whitelist must therefore pin trusted swap-router/V4Utils
  ///      implementations whose own routing policy is acceptable.
  function _run(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    Swap[] memory swaps
  ) private returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;

    ISharedConfigManager configManager;
    if (swaps.length > 0) {
      configManager = ISharedVault(address(this)).configManager();
      require(configManager.isWhitelistedSwapRouter(swapRouter), ISharedCommon.InvalidSwapRouter(swapRouter));
    }

    address[] memory intTokens = new address[](swaps.length);
    uint256[] memory intBalances = new uint256[](swaps.length);
    uint256 intCount;

    for (uint256 i; i < swaps.length;) {
      Swap memory swapParam = swaps[i];
      require(
        _isSwapInputAllowed(token0, token1, swapParam.tokenIn, swaps, i)
          && _isSwapOutputAllowed(token0, token1, swapParam.tokenOut, swaps, i),
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

      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        configManager,
        swapRouter,
        swapParam.tokenIn,
        swapParam.tokenOut,
        amountIn,
        swapParam.amountOutMin,
        swapParam.swapData,
        i
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

  function _isSwapInputAllowed(address token0, address token1, address tokenIn, Swap[] memory swaps, uint256 index)
    private
    pure
    returns (bool)
  {
    if (tokenIn == token0 || tokenIn == token1) return true;
    for (uint256 i; i < index;) {
      if (swaps[i].tokenOut == tokenIn) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _isSwapOutputAllowed(address token0, address token1, address tokenOut, Swap[] memory swaps, uint256 index)
    private
    pure
    returns (bool)
  {
    if (tokenOut == token0 || tokenOut == token1) return true;
    if (tokenOut == address(0)) return false;
    for (uint256 i = index + 1; i < swaps.length;) {
      if (swaps[i].tokenIn == tokenOut) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _swap(
    ISharedConfigManager configManager,
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
    swapData = SharedSwapDataSignature.verify(
      configManager, address(this), swapRouter, tokenIn, tokenOut, amountIn, amountOutMin, swapData
    );
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
