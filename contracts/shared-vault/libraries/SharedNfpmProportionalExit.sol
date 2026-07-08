// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { SharedStrategyFees } from "./SharedStrategyFees.sol";

/// @title SharedNfpmProportionalExit
/// @notice Pre-collect accrued fees → take perf/platform fees → decrease proportional liquidity → collect
///         principal. Fees are settled via `SharedStrategyFees` (direct proportional transfer of each token's
///         fee slice to platform / vault owner), NOT the public-vault `LpFeeTaker` swap-and-consolidate path.
library SharedNfpmProportionalExit {
  /// @notice Pre-collect accrued fees into vault idle balance and take perf/platform fees.
  /// @dev Called from strategy.collectFees() which is delegatecalled by SharedVault.withdraw() BEFORE
  ///      the idleBefore snapshot so that accumulated fees are distributed proportionally by share ratio.
  ///
  ///      **Fee-sync safety**: Both the canonical Uniswap V3 NFPM and Slipstream/Aerodrome NFPM call
  ///      `pool.burn(tickLower, tickUpper, 0)` inside their `collect()` implementations when
  ///      `position.liquidity > 0`. This pool call updates `feeGrowthInsideLast*` and computes the
  ///      pending fee-growth delta into `tokensOwed*`, so `collect(type(uint128).max, type(uint128).max)`
  ///      here captures ALL accrued fees — both the previously-synced `tokensOwed*` stored on the NFT
  ///      and any fee growth that accumulated since the last sync. No separate pre-sync step is needed.
  ///
  ///      Because this function and the subsequent `decreaseLiquidityProportional` run in the same
  ///      transaction, zero additional swap fees can accrue between them, so the withdrawer cannot
  ///      receive fees beyond their proportional share via the later `collect(type(uint128).max)`.
  function collectAccumulatedFees(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    ICommon.FeeConfig memory perfFeeConfig
  ) internal {
    (uint256 collected0, uint256 collected1) = INFPM(nfpm).collect(
      INFPM.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    if (collected0 == 0 && collected1 == 0) return;

    // Perf-only (platform + vault owner); no gas fee on the withdraw fee-sync.
    ICommon.FeeConfig memory perfOnly = perfFeeConfig;
    perfOnly.gasFeeX64 = 0;
    perfOnly.gasFeeRecipient = address(0);
    // Direct proportional transfer of each token's fee slice to platform / vault owner — no swap, no
    // pool interaction. The clamp in `applyFees` guarantees total fee <= collected, so a withdraw can
    // never revert from over-drawn fees (which previously could brick the vault for all share holders).
    SharedStrategyFees.applyFees(token0, collected0, token1, collected1, perfOnly);
  }

  /// @dev Fees are pre-collected by `collectAccumulatedFees` before the idle snapshot in SharedVault.withdraw(),
  ///      so this function only decreases liquidity, collects the resulting principal, and (when configured)
  ///      takes a gas fee on the principal. On the withdraw/exit path `performanceFeeConfig()` sets
  ///      `gasFeeX64 = 0`, so the gas branch is inert there; it remains for callers that pass a gas fee.
  function decreaseLiquidityProportional(
    address nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 amount0Min,
    uint256 amount1Min,
    address token0,
    address token1,
    ICommon.FeeConfig memory perfFeeConfig
  ) internal {
    INFPM(nfpm).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidityToRemove,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: block.timestamp
      })
    );

    (uint256 principal0, uint256 principal1) = INFPM(nfpm).collect(
      INFPM.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );

    if (
      perfFeeConfig.gasFeeX64 > 0 && perfFeeConfig.gasFeeRecipient != address(0) && (principal0 > 0 || principal1 > 0)
    ) {
      ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
        vaultOwnerFeeBasisPoint: 0,
        vaultOwner: address(0),
        platformFeeBasisPoint: 0,
        platformFeeRecipient: address(0),
        gasFeeX64: perfFeeConfig.gasFeeX64,
        gasFeeRecipient: perfFeeConfig.gasFeeRecipient
      });
      SharedStrategyFees.applyFees(token0, principal0, token1, principal1, gasOnly);
    }
  }
}
