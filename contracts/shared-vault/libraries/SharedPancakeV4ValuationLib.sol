// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { PoolId } from "infinity-core/src/types/PoolId.sol";
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { Tick } from "infinity-core/src/pool-cl/libraries/Tick.sol";
import { ICLPositionManager } from "infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";

/// @title SharedPancakeV4ValuationLib
/// @notice Read-only valuation + fee-growth math for PancakeSwap Infinity CL positions, split out of
///         `SharedPancakeV4StrategyLib` to keep that (size-constrained) strategy library under the
///         EIP-170 24_576-byte limit. Pure/view only; reads exclusively from the supplied `posm` and
///         its CL pool manager. `SharedPancakeV4StrategyLib` exposes thin getter stubs delegating here,
///         so the strategy ABI is unchanged. NOTE: separately deployed/linked — deployment and config
///         tooling must link it alongside `SharedPancakeV4StrategyLib`.
library SharedPancakeV4ValuationLib {
  using CLPositionInfoLibrary for CLPositionInfo;

  function getPositionAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1) {
    (uint256 principal0, uint256 principal1, uint256 fees0, uint256 fees1) = _positionAmountsSplit(posm, tokenId);
    amount0 = principal0 + fees0;
    amount1 = principal1 + fees1;
  }

  function getPositionPrincipalAmounts(address posm, uint256 tokenId)
    external
    view
    returns (uint256 amount0, uint256 amount1)
  {
    (amount0, amount1,,) = _positionAmountsSplit(posm, tokenId);
  }

  function getPositionAmountsSplit(address posm, uint256 tokenId)
    external
    view
    returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
  {
    uint256 fees0;
    uint256 fees1;
    (principal0, principal1, fees0, fees1) = _positionAmountsSplit(posm, tokenId);
    total0 = principal0 + fees0;
    total1 = principal1 + fees1;
  }

  /// @dev The failed-collect fallback is only a gate for whether to re-revert a hook failure. Use a
  ///      non-wrapping positive-delta check here so feeGrowthInside < feeGrowthInsideLast does not
  ///      look like near-uint256.max pending fees and brick an otherwise zero-fee position. Normal
  ///      valuation still uses `_feeOwed`'s modulo arithmetic to mirror Pancake CL fee accounting.
  function hasCollectableFeesForFailedCollect(address posm, uint256 tokenId) external view returns (bool) {
    ICLPositionManager pm = ICLPositionManager(posm);
    (PoolKey memory poolKey, CLPositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    if (CLPositionInfo.unwrap(positionInfo) == 0) return false;

    (,,, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,) = pm.positions(tokenId);
    if (liquidity == 0) return false;

    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();
    ICLPoolManager manager = ICLPoolManager(address(poolKey.poolManager));
    PoolId poolId = poolKey.toId();
    (, int24 tickCurrent,,) = manager.getSlot0(poolId);
    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
      _getFeeGrowthInside(manager, poolId, tickLower, tickUpper, tickCurrent);

    return _hasPositiveCollectFeeDelta(feeGrowthInside0X128, feeGrowthInside0LastX128, liquidity)
      || _hasPositiveCollectFeeDelta(feeGrowthInside1X128, feeGrowthInside1LastX128, liquidity);
  }

  function _positionAmountsSplit(address posm, uint256 tokenId)
    private
    view
    returns (uint256 principal0, uint256 principal1, uint256 fees0, uint256 fees1)
  {
    ICLPositionManager pm = ICLPositionManager(posm);
    PoolKey memory poolKey;
    CLPositionInfo positionInfo;
    try pm.getPoolAndPositionInfo(tokenId) returns (PoolKey memory key, CLPositionInfo info) {
      poolKey = key;
      positionInfo = info;
    } catch {
      return (0, 0, 0, 0);
    }

    // An empty / burned tokenId carries a zero `CLPositionInfo`. `getPoolAndPositionInfo` above returns
    // zeros for such a tokenId WITHOUT reverting, but the `pm.positions(tokenId)` read below reverts with
    // `InvalidTokenID()` (CLPositionManager checks `CLPositionInfo.unwrap(info) == 0`). Since this view is
    // reached from `getPositionAmounts`/`getPositionPrincipalAmounts` during `deposit()`/`withdraw()`/preview,
    // an unguarded revert here would brick valuation for the whole vault. Short-circuit to zeros instead —
    // parity with the never-reverting Uniswap-V4 sibling (`SharedV4ValuationLib._positionAmountsSplit`,
    // which sources liquidity via the revert-safe `getPositionLiquidity`).
    if (CLPositionInfo.unwrap(positionInfo) == 0) return (0, 0, 0, 0);

    // F6: read liquidity + last-fee-growth ONCE from positions() and use the same liquidity snapshot
    // for both principal and fee valuation. Previously principal used getPositionLiquidity() while the
    // fee path independently re-read liquidity from positions(), which could disagree.
    (,,, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,) = pm.positions(tokenId);
    if (liquidity == 0) return (0, 0, 0, 0);

    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();

    ICLPoolManager manager = ICLPoolManager(address(poolKey.poolManager));
    PoolId poolId = poolKey.toId();
    (uint160 sqrtPriceX96, int24 tickCurrent,,) = manager.getSlot0(poolId);

    (principal0, principal1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity
    );

    // PancakeSwap Infinity's CL PoolManager does NOT expose a `getFeeGrowthInside` getter (unlike
    // Uniswap V4's StateLibrary), so reconstruct fee-growth-inside [tickLower, tickUpper] from the
    // canonical `[global - below - above]` decomposition using each boundary tick's
    // `feeGrowthOutside` snapshot. All arithmetic wraps (mod 2^256) to mirror the pool's accounting.
    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
      _getFeeGrowthInside(manager, poolId, tickLower, tickUpper, tickCurrent);
    fees0 = _feeOwed(feeGrowthInside0X128, feeGrowthInside0LastX128, liquidity);
    fees1 = _feeOwed(feeGrowthInside1X128, feeGrowthInside1LastX128, liquidity);
  }

  function _hasPositiveCollectFeeDelta(uint256 feeGrowthInsideX128, uint256 feeGrowthInsideLastX128, uint256 liquidity)
    private
    pure
    returns (bool)
  {
    if (liquidity == 0 || feeGrowthInsideX128 <= feeGrowthInsideLastX128) return false;
    return FullMath.mulDiv(feeGrowthInsideX128 - feeGrowthInsideLastX128, liquidity, FixedPoint128.Q128) != 0;
  }

  /// @dev Reconstructs fee-growth-inside [tickLower, tickUpper] from the pool's global fee growth and
  ///      each boundary tick's `feeGrowthOutside` snapshot. Mirrors Uniswap V3 / PancakeSwap CL
  ///      `Tick.getFeeGrowthInside`. All subtraction is intentionally unchecked so it wraps mod 2^256,
  ///      matching the pool's own (overflow-tolerant) fee accounting.
  function _getFeeGrowthInside(
    ICLPoolManager manager,
    PoolId poolId,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) private view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    unchecked {
      Tick.Info memory lower = manager.getPoolTickInfo(poolId, tickLower);
      Tick.Info memory upper = manager.getPoolTickInfo(poolId, tickUpper);
      (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(poolId);

      uint256 feeGrowthBelow0X128;
      uint256 feeGrowthBelow1X128;
      if (tickCurrent >= tickLower) {
        feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (tickCurrent < tickUpper) {
        feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }

  /// @dev F7-parity with SharedV3Strategy: the fee-growth subtraction wraps by design (matches PancakeSwap
  ///      Infinity CL), but the pending fee is accumulated in uint256 and NOT cast to uint128. A reverting
  ///      SafeCast here would make `getPositionAmounts` / `getPositionPrincipalAmounts` — reached on
  ///      `deposit()` and preview via `_positionAmountsSplit` — revert under extreme/wrapped fee-growth,
  ///      which could brick deposits/valuation for the whole vault. Valuing in uint256 cannot revert.
  function _feeOwed(uint256 feeGrowthInsideX128, uint256 feeGrowthInsideLastX128, uint256 liquidity)
    private
    pure
    returns (uint256)
  {
    if (liquidity == 0) return 0;
    unchecked {
      return FullMath.mulDiv(feeGrowthInsideX128 - feeGrowthInsideLastX128, liquidity, FixedPoint128.Q128);
    }
  }
}
