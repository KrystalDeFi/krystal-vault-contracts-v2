// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

/// @title SharedV4ValuationLib
/// @notice Read-only valuation + fee-growth math for Uniswap V4 positions, split out of
///         `SharedV4StrategyLib` so that the (deployment-size-constrained) strategy library stays
///         under the EIP-170 24_576-byte limit. This code is pure/view and never touches vault state
///         or the swap pipeline; it reads exclusively from the supplied `posm` and its pool manager.
///         `SharedV4StrategyLib` exposes thin getter stubs that delegate here, so the strategy ABI is
///         unchanged. NOTE: this is a separately deployed/linked library — deployment and config
///         tooling must link it alongside `SharedV4StrategyLib`.
library SharedV4ValuationLib {
  using PoolIdLibrary for PoolKey;
  using PositionInfoLibrary for PositionInfo;
  using StateLibrary for IPoolManager;

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
  ///      valuation still uses `_feeOwed`'s modulo arithmetic to mirror V4 fee accounting.
  function hasCollectableFeesForFailedCollect(address posm, uint256 tokenId) external view returns (bool) {
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, PositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();

    IPoolManager manager = pm.poolManager();
    PoolId poolId = poolKey.toId();
    (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
      manager.getPositionInfo(poolId, address(posm), tickLower, tickUpper, bytes32(tokenId));
    if (liquidity == 0) return false;

    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
      manager.getFeeGrowthInside(poolId, tickLower, tickUpper);

    return _hasPositiveCollectFeeDelta(feeGrowthInside0X128, feeGrowthInside0LastX128, liquidity)
      || _hasPositiveCollectFeeDelta(feeGrowthInside1X128, feeGrowthInside1LastX128, liquidity);
  }

  function _positionAmountsSplit(address posm, uint256 tokenId)
    private
    view
    returns (uint256 principal0, uint256 principal1, uint256 fees0, uint256 fees1)
  {
    IPositionManager pm = IPositionManager(posm);
    PoolKey memory poolKey;
    PositionInfo positionInfo;
    try pm.getPoolAndPositionInfo(tokenId) returns (PoolKey memory key, PositionInfo info) {
      poolKey = key;
      positionInfo = info;
    } catch {
      return (0, 0, 0, 0);
    }
    uint128 liquidity = pm.getPositionLiquidity(tokenId);
    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();

    IPoolManager manager = pm.poolManager();
    PoolId poolId = poolKey.toId();
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);

    if (liquidity > 0) {
      (principal0, principal1) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity
      );
    }

    (fees0, fees1) = _uncollectedFees(pm, manager, poolId, tickLower, tickUpper, tokenId);
  }

  function _uncollectedFees(
    IPositionManager posm,
    IPoolManager manager,
    PoolId poolId,
    int24 tickLower,
    int24 tickUpper,
    uint256 tokenId
  ) private view returns (uint256 fee0, uint256 fee1) {
    (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
      manager.getPositionInfo(poolId, address(posm), tickLower, tickUpper, bytes32(tokenId));
    if (liquidity == 0) return (0, 0);

    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
      manager.getFeeGrowthInside(poolId, tickLower, tickUpper);

    fee0 = _feeOwed(feeGrowthInside0X128, feeGrowthInside0LastX128, liquidity);
    fee1 = _feeOwed(feeGrowthInside1X128, feeGrowthInside1LastX128, liquidity);
  }

  function _hasPositiveCollectFeeDelta(uint256 feeGrowthInsideX128, uint256 feeGrowthInsideLastX128, uint256 liquidity)
    private
    pure
    returns (bool)
  {
    if (liquidity == 0 || feeGrowthInsideX128 <= feeGrowthInsideLastX128) return false;
    return FullMath.mulDiv(feeGrowthInsideX128 - feeGrowthInsideLastX128, liquidity, FixedPoint128.Q128) != 0;
  }

  /// @dev F7-parity with SharedV3Strategy: the fee-growth subtraction wraps by design (matches Uniswap V4),
  ///      but the pending fee is accumulated in uint256 and NOT cast to uint128. A reverting SafeCast here
  ///      would make `getPositionAmounts` / `getPositionPrincipalAmounts` — reached on `deposit()` and
  ///      preview via `_positionAmountsSplit` — revert under extreme/wrapped fee-growth, which could brick
  ///      deposits/valuation for the whole vault. Valuing in uint256 cannot revert.
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
