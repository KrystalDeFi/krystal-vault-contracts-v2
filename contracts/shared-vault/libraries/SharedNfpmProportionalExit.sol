// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ILpFeeTaker } from "../../public-vault/interfaces/strategies/ILpFeeTaker.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";

/// @title SharedNfpmProportionalExit
/// @notice Mirrors public `LpStrategy._decreaseLiquidity`: collect accrued fees → `LpFeeTaker.takeFees` (perf/platform) →
///         decrease proportional liquidity → collect principal → optional gas fee on principal via `LpFeeTaker`.
library SharedNfpmProportionalExit {
  /// @notice Pre-collect accrued fees into vault idle balance and take perf/platform fees.
  /// @dev Called from strategy.collectFees() which is delegatecalled by SharedVault.withdraw() BEFORE
  ///      the idleBefore snapshot so that accumulated fees are distributed proportionally by share ratio.
  function collectAccumulatedFees(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    address pool,
    address lpFeeTaker,
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

    ICommon.FeeConfig memory perfOnly = perfFeeConfig;
    perfOnly.gasFeeX64 = 0;
    perfOnly.gasFeeRecipient = address(0);

    if (
      (collected0 > 0 || collected1 > 0) && (perfOnly.vaultOwnerFeeBasisPoint > 0 || perfOnly.platformFeeBasisPoint > 0)
    ) {
      _safeResetAndApprove(IERC20(token0), lpFeeTaker, collected0);
      _safeResetAndApprove(IERC20(token1), lpFeeTaker, collected1);
      ILpFeeTaker(lpFeeTaker).takeFees(token0, collected0, token1, collected1, perfOnly, token0, pool, address(0));
    }
  }

  /// @dev Pulls performance/platform/owner fees from collected fee amounts; gas fee is taken from principal after decrease (public pattern).
  ///      Fees are pre-collected by `collectAccumulatedFees` before the idle snapshot in SharedVault.withdraw(),
  ///      so this function only decreases liquidity and collects the resulting principal.
  function decreaseLiquidityProportional(
    address nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 amount0Min,
    uint256 amount1Min,
    address token0,
    address token1,
    address pool,
    address lpFeeTaker,
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
      _safeResetAndApprove(IERC20(token0), lpFeeTaker, principal0);
      _safeResetAndApprove(IERC20(token1), lpFeeTaker, principal1);
      ILpFeeTaker(lpFeeTaker).takeFees(token0, principal0, token1, principal1, gasOnly, token0, pool, address(0));
    }
  }

  function _safeResetAndApprove(IERC20 token, address spender, uint256 value) private {
    if (value == 0) return;
    address(token).call(abi.encodeWithSelector(token.approve.selector, spender, 0));
    (bool ok, bytes memory ret) = address(token).call(abi.encodeWithSelector(token.approve.selector, spender, value));
    require(ok && (ret.length == 0 || abi.decode(ret, (bool))), ICommon.ApproveFailed());
  }
}
