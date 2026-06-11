// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedPancakeV4Utils } from "../interfaces/ISharedPancakeV4Utils.sol";
import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedV4Utils } from "../interfaces/ISharedV4Utils.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { SharedStrategyFeeConfig } from "./SharedStrategyFeeConfig.sol";
import { SharedStrategyFees } from "./SharedStrategyFees.sol";
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

  /// @dev Protocol-neutral input descriptor: an `InputTokenParams` entry with the currency already
  ///      mapped to its vault token (native → WETH). Mirrors the `Swap` normalization pattern.
  struct Input {
    address token;
    uint256 amount;
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
      swapRouter,
      token0,
      token1,
      amount0,
      amount1,
      new address[](0),
      new uint256[](0),
      _normalizeV4(swapParams, ISharedVault(address(this)).weth())
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
      swapRouter,
      token0,
      token1,
      amount0,
      amount1,
      new address[](0),
      new uint256[](0),
      _normalizePancake(swapParams, ISharedVault(address(this)).weth())
    );
  }

  /// @dev `execute` variant for the swap-and-mint / swap-and-increase entrypoints: validates and
  ///      folds `inputTokens` into the pipeline before the hops run. Every positive-amount input
  ///      must be a vault token; after the (cap-validated) gas-fee skim, pool-token inputs fold into
  ///      the running `total0`/`total1` while any OTHER vault token — the "fund the LP from a third
  ///      vault token" flow (V3/Aerodrome `swapSourceToken` parity) — seeds the intermediate ledger
  ///      and must be consumed down to EXACTLY zero by signed swap hops. That ledger rule is the
  ///      anti-siphon guard: historically a non-pool input could pay `amount * gasFeeX64 / Q64` to
  ///      the fee recipient while the remainder dangled outside the LP accounting; now a dangling
  ///      remainder reverts the whole operation, fee skim included. Zero-amount entries are
  ///      tolerated (no-op for fee, totals, and ledger alike).
  function executeWithInputs(
    address swapRouter,
    address token0,
    address token1,
    ISharedV4Utils.InputTokenParams[] memory inputTokens,
    uint64 gasFeeX64,
    ISharedV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    address weth = ISharedVault(address(this)).weth();
    Input[] memory inputs = new Input[](inputTokens.length);
    for (uint256 i; i < inputTokens.length;) {
      inputs[i] = Input(_vaultToken(UniCurrency.unwrap(inputTokens[i].token), weth), inputTokens[i].amount);
      unchecked {
        i++;
      }
    }
    return _runWithInputs(swapRouter, token0, token1, inputs, gasFeeX64, _normalizeV4(swapParams, weth));
  }

  /// @dev Pancake twin of `executeWithInputs` (infinity-core Currency normalization).
  function executePancakeWithInputs(
    address swapRouter,
    address token0,
    address token1,
    ISharedPancakeV4Utils.InputTokenParams[] memory inputTokens,
    uint64 gasFeeX64,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    address weth = ISharedVault(address(this)).weth();
    Input[] memory inputs = new Input[](inputTokens.length);
    for (uint256 i; i < inputTokens.length;) {
      inputs[i] = Input(_vaultToken(PancakeCurrency.unwrap(inputTokens[i].token), weth), inputTokens[i].amount);
      unchecked {
        i++;
      }
    }
    return _runWithInputs(swapRouter, token0, token1, inputs, gasFeeX64, _normalizePancake(swapParams, weth));
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

  /// @dev Shared body of `executeWithInputs` / `executePancakeWithInputs`: split the (post-fee)
  ///      inputs into pool totals + ledger seeds, then run the hop loop.
  function _runWithInputs(
    address swapRouter,
    address token0,
    address token1,
    Input[] memory inputs,
    uint64 gasFeeX64,
    Swap[] memory swaps
  ) private returns (uint256 total0, uint256 total1) {
    (uint256 amount0, uint256 amount1, address[] memory seedTokens, uint256[] memory seedAmounts) =
      _takeInputGasFeesAndSplit(token0, token1, inputs, gasFeeX64);
    return _run(swapRouter, token0, token1, amount0, amount1, seedTokens, seedAmounts, swaps);
  }

  /// @dev Validates each positive-amount input as a vault token, skims the (cap-validated) input gas
  ///      fee per entry, then folds the post-fee amount into `amount0`/`amount1` (pool tokens) or the
  ///      returned seed arrays (non-pool vault tokens, duplicate entries merged). The seeds
  ///      pre-populate `_run`'s intermediate ledger, whose final exact-zero check forces signed swap
  ///      hops to consume them in full.
  function _takeInputGasFeesAndSplit(address token0, address token1, Input[] memory inputs, uint64 gasFeeX64)
    private
    returns (uint256 amount0, uint256 amount1, address[] memory seedTokens, uint256[] memory seedAmounts)
  {
    address gasFeeRecipient;
    if (gasFeeX64 > 0) (gasFeeX64, gasFeeRecipient) = SharedStrategyFeeConfig.validateGasFeeX64(gasFeeX64);
    seedTokens = new address[](inputs.length);
    seedAmounts = new uint256[](inputs.length);
    uint256 seedCount;
    for (uint256 i; i < inputs.length;) {
      uint256 amount = inputs[i].amount;
      if (amount > 0) {
        address token = inputs[i].token;
        require(ISharedVault(address(this)).isVaultToken(token), ISharedStrategy.InvalidPoolTokens());
        if (gasFeeX64 > 0) amount -= _takeSingleTokenGasFee(token, amount, gasFeeX64, gasFeeRecipient);
        if (token == token0) {
          amount0 += amount;
        } else if (token == token1) {
          amount1 += amount;
        } else {
          uint256 idx = _findIntermediate(seedTokens, seedCount, token);
          if (idx == seedCount) {
            seedTokens[seedCount] = token;
            unchecked {
              seedCount++;
            }
          }
          seedAmounts[idx] += amount;
        }
      }
      unchecked {
        i++;
      }
    }
    // Shrink (never grow) the over-allocated seed arrays to the merged entry count in place.
    assembly ("memory-safe") {
      mstore(seedTokens, seedCount)
      mstore(seedAmounts, seedCount)
    }
  }

  function _takeSingleTokenGasFee(address token, uint256 amount, uint64 gasFeeX64, address gasFeeRecipient)
    private
    returns (uint256 gasFee)
  {
    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: gasFeeRecipient
    });
    (gasFee,) = SharedStrategyFees.applyFees(token, amount, address(0), 0, gasOnly);
  }

  /// @dev The single swap-pipeline implementation shared by both protocols. Validates the top-level
  ///      immutable `swapRouter` is whitelisted, then for each hop enforces input/output token
  ///      reachability, draws the input from principal (token0/token1) or a tracked intermediate
  ///      balance (chain outputs and seeded non-pool inputs alike), executes the swap, and books the
  ///      deltas. After the loop every intermediate balance must net to zero (no token left
  ///      stranded) — for seeded inputs this is what forces the full declared amount into the pool
  ///      currencies.
  ///
  ///      Trust boundary: `swapData` is opaque calldata executed only against `swapRouter`. This
  ///      pipeline does not parse or re-check any downstream router/adapter target embedded inside
  ///      that calldata; the config-manager whitelist must therefore pin trusted swap-router/V4Utils
  ///      implementations whose own routing policy is acceptable.
  ///
  ///      Signing note: `Swap.amountIn` is forwarded to `SharedSwapDataSignature.verify` verbatim —
  ///      it is never replaced by an on-chain computed balance (mirrors the V3/Aerodrome
  ///      `_swapForWithdraw` signed-amount rule). The backend folds withdraw-liquidity slippage into
  ///      the signed amount, so the realized total may exceed it; the `amountIn <= total` guard only
  ///      requires coverage, and the un-swapped remainder stays in the returned totals.
  ///      `Swap.amountIn == 0` means "no swap for this hop" (its `amountOutMin` must be 0) — it is
  ///      NOT resolved to the available balance.
  function _run(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    address[] memory seedTokens,
    uint256[] memory seedAmounts,
    Swap[] memory swaps
  ) private returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;

    ISharedConfigManager configManager;
    if (swaps.length > 0) {
      configManager = ISharedVault(address(this)).configManager();
      require(configManager.isWhitelistedSwapRouter(swapRouter), ISharedCommon.InvalidSwapRouter(swapRouter));
    }

    uint256 intCount = seedTokens.length;
    address[] memory intTokens = new address[](swaps.length + intCount);
    uint256[] memory intBalances = new uint256[](swaps.length + intCount);
    for (uint256 j; j < intCount;) {
      intTokens[j] = seedTokens[j];
      intBalances[j] = seedAmounts[j];
      unchecked {
        j++;
      }
    }

    for (uint256 i; i < swaps.length;) {
      Swap memory swapParam = swaps[i];
      require(
        _isSwapInputAllowed(token0, token1, swapParam.tokenIn, swaps, i, seedTokens)
          && _isSwapOutputAllowed(token0, token1, swapParam.tokenOut, swaps, i),
        ISharedStrategy.InvalidPoolTokens()
      );

      // `swapParam.amountIn` is signature-bound and forwarded to `_swap` verbatim — never replaced
      // by a computed balance. The tracked total only needs to COVER it (the backend folds
      // withdraw-liquidity slippage into the signed amount); the remainder stays in the totals.
      uint256 inIdx;
      bool inIsIntermediate;
      if (swapParam.tokenIn == token0) {
        require(swapParam.amountIn <= total0, ISharedCommon.InvalidAmount());
      } else if (swapParam.tokenIn == token1) {
        require(swapParam.amountIn <= total1, ISharedCommon.InvalidAmount());
      } else {
        inIsIntermediate = true;
        inIdx = _findIntermediate(intTokens, intCount, swapParam.tokenIn);
        uint256 tracked = inIdx < intCount ? intBalances[inIdx] : 0;
        require(swapParam.amountIn <= tracked, ISharedCommon.InvalidAmount());
      }

      if (swapParam.amountIn == 0) {
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
        swapParam.amountIn,
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

  /// @dev A hop may draw from a pool token, a seeded non-pool input, or a PRIOR hop's declared
  ///      output. Everything else has no tracked balance to spend and is rejected outright.
  function _isSwapInputAllowed(
    address token0,
    address token1,
    address tokenIn,
    Swap[] memory swaps,
    uint256 index,
    address[] memory seedTokens
  ) private pure returns (bool) {
    if (tokenIn == token0 || tokenIn == token1) return true;
    if (_findIntermediate(seedTokens, seedTokens.length, tokenIn) < seedTokens.length) return true;
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
    // No swap occurs on this path, so no signature is required; amountOutMin must be zero.
    if (amountIn == 0 || swapData.length == 0 || tokenOut == address(0)) {
      require(amountOutMin == 0, ISharedCommon.InsufficientOutput());
      return (0, 0);
    }
    require(tokenIn != tokenOut, ISharedCommon.InvalidOperation());

    swapData = SharedSwapDataSignature.verify(
      configManager, address(this), swapRouter, tokenIn, tokenOut, amountIn, amountOutMin, swapData
    );
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
    // One event per executed hop (no-op hops return above). ISharedPancakeV4Utils.Swap has the
    // same signature, so this single emit serves both the Uniswap V4 and Pancake entry points
    // with an identical topic0.
    emit ISharedV4Utils.Swap(tokenIn, tokenOut, amountInDelta, amountOutDelta);
  }
}
