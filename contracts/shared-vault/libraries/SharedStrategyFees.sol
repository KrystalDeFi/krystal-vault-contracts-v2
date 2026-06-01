// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { IFeeTaker } from "../../public-vault/interfaces/strategies/IFeeTaker.sol";

/// @title SharedStrategyFees
/// @notice Canonical fee-application model for the shared-vault strategies (V3, Aerodrome, V4, PancakeV4).
///         Replaces the public-vault `LpFeeTaker` for shared strategies: instead of swapping the
///         non-principal fee slice into a single "principal" token, it transfers the platform /
///         vault-owner / gas fee slices of token0 and token1 DIRECTLY to their recipients. Both fee
///         recipients (platform + vault owner) accept any of the vault's tokens, so no swap, price
///         validation, or pool interaction is needed — the previous `LpFeeTaker` swap path was redundant.
/// @dev Runs in the vault's context (the strategies/libs that call this are delegatecalled by SharedVault),
///      so `address(this)` is the vault and the fee tokens are pulled from the vault's idle balance.
///
///      Fees are applied SEQUENTIALLY against a running remainder (platform → owner → gas). Each share is
///      computed from the ORIGINAL amount and clamped to whatever is left (`if (fee > remaining) fee =
///      remaining`). Because every share is computed from the original amount, the clamp only ever caps the
///      LAST fee type(s) when the configured bps sum exceeds 100% — total fee can NEVER exceed the collected
///      amount, so the `collected - fee` accounting downstream can never underflow. This is the same model
///      the V4/Pancake libs apply inline, now unified across every shared strategy, eliminating the previous
///      revert-vs-clamp divergence (V3/Aerodrome used to route through `LpFeeTaker`, which summed fees without
///      clamping and therefore needed an explicit `platform+owner+gas <= 100%` revert guard). `gasFeeX64` is a
///      Q64 fraction and, like platform/owner bps, is clamped rather than reverted.
library SharedStrategyFees {
  using SafeERC20 for IERC20;

  uint256 private constant Q64 = 0x10000000000000000;

  event FeeCollected(
    address indexed vaultAddress,
    IFeeTaker.FeeType indexed feeType,
    address indexed recipient,
    address token,
    uint256 amount
  );

  /// @notice Apply platform/owner/gas fees to (token0, amount0) and (token1, amount1), transferring each fee
  ///         slice directly to its recipient.
  /// @return feeTaken0 Total fee taken from token0 (platform + owner + gas), always <= amount0
  /// @return feeTaken1 Total fee taken from token1 (platform + owner + gas), always <= amount1
  function applyFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    ICommon.FeeConfig memory fc
  ) internal returns (uint256 feeTaken0, uint256 feeTaken1) {
    uint256 remaining0 = amount0;
    uint256 remaining1 = amount1;

    if (fc.platformFeeBasisPoint > 0 && fc.platformFeeRecipient != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.platformFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.platformFeeBasisPoint, 10_000);
      if (fee0 > remaining0) fee0 = remaining0;
      if (fee1 > remaining1) fee1 = remaining1;
      if (fee0 > 0) _transfer(IFeeTaker.FeeType.PLATFORM, fc.platformFeeRecipient, token0, fee0);
      if (fee1 > 0) _transfer(IFeeTaker.FeeType.PLATFORM, fc.platformFeeRecipient, token1, fee1);
      feeTaken0 += fee0;
      feeTaken1 += fee1;
      remaining0 -= fee0;
      remaining1 -= fee1;
    }
    if (fc.vaultOwnerFeeBasisPoint > 0 && fc.vaultOwner != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.vaultOwnerFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.vaultOwnerFeeBasisPoint, 10_000);
      if (fee0 > remaining0) fee0 = remaining0;
      if (fee1 > remaining1) fee1 = remaining1;
      if (fee0 > 0) _transfer(IFeeTaker.FeeType.OWNER, fc.vaultOwner, token0, fee0);
      if (fee1 > 0) _transfer(IFeeTaker.FeeType.OWNER, fc.vaultOwner, token1, fee1);
      feeTaken0 += fee0;
      feeTaken1 += fee1;
      remaining0 -= fee0;
      remaining1 -= fee1;
    }
    if (fc.gasFeeX64 > 0 && fc.gasFeeRecipient != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.gasFeeX64, Q64);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.gasFeeX64, Q64);
      if (fee0 > remaining0) fee0 = remaining0;
      if (fee1 > remaining1) fee1 = remaining1;
      if (fee0 > 0) _transfer(IFeeTaker.FeeType.GAS, fc.gasFeeRecipient, token0, fee0);
      if (fee1 > 0) _transfer(IFeeTaker.FeeType.GAS, fc.gasFeeRecipient, token1, fee1);
      feeTaken0 += fee0;
      feeTaken1 += fee1;
    }
  }

  function _transfer(IFeeTaker.FeeType feeType, address recipient, address token, uint256 amount) private {
    IERC20(token).safeTransfer(recipient, amount);
    emit FeeCollected(address(this), feeType, recipient, token, amount);
  }
}
