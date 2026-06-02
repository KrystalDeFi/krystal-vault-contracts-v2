// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { ISharedPancakeV4Utils } from "../interfaces/ISharedPancakeV4Utils.sol";
import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyFees } from "../libraries/SharedStrategyFees.sol";

import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { PoolId } from "infinity-core/src/types/PoolId.sol";
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { Tick } from "infinity-core/src/pool-cl/libraries/Tick.sol";
import { ICLPositionManager } from "infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";
import { IPositionManagerPermit2 } from "infinity-periphery/src/interfaces/IPositionManagerPermit2.sol";

library PancakeV4Actions {
  uint8 internal constant INCREASE_LIQUIDITY = 0x00;
  uint8 internal constant DECREASE_LIQUIDITY = 0x01;
  uint8 internal constant MINT_POSITION = 0x02;
  uint8 internal constant SETTLE_PAIR = 0x0d;
  uint8 internal constant TAKE_PAIR = 0x11;
  uint8 internal constant CLOSE_CURRENCY = 0x12;
}

library SharedPancakeV4StrategyLib {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;
  using CLPositionInfoLibrary for CLPositionInfo;

  /// @dev See SharedV4StrategyLib.depositProportional for the full slippage rationale. The previous
  ///      liquidity post-check compared the requested liquidity against a fraction of itself and was
  ///      always satisfied; this enforces a real per-token floor on the amounts ACTUALLY consumed
  ///      (balance deltas) against the amounts quoted for `liquidityToAdd`, with the `slippageBps`
  ///      haircut, and tolerates single-sided positions. It cannot by itself defeat a cross-tx spot
  ///      sandwich (adding CL liquidity does not move price), so callers must pass a conservative bps.
  function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps)
    external
  {
    if (amount0 == 0 && amount1 == 0) return;

    _requireWhitelistedPosm(posm);

    ICLPositionManager pm = ICLPositionManager(posm);
    (PoolKey memory poolKey, CLPositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);

    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());

    (uint160 sqrtPriceX96,,,) = ICLPoolManager(address(poolKey.poolManager)).getSlot0(poolKey.toId());
    uint160 sqrtLower = TickMath.getSqrtPriceAtTick(positionInfo.tickLower());
    uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(positionInfo.tickUpper());
    uint128 liquidityToAdd =
      LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
    if (liquidityToAdd == 0) return;

    (uint256 expected0, uint256 expected1) =
      LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtLower, sqrtUpper, liquidityToAdd);

    uint256 balance0Before = IERC20(token0).balanceOf(address(this));
    uint256 balance1Before = IERC20(token1).balanceOf(address(this));

    address permit2Addr = address(IPositionManagerPermit2(posm).permit2());
    if (amount0 > 0) {
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0) {
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }

    bytes memory actions = abi.encodePacked(
      uint8(PancakeV4Actions.INCREASE_LIQUIDITY),
      uint8(PancakeV4Actions.CLOSE_CURRENCY),
      uint8(PancakeV4Actions.CLOSE_CURRENCY)
    );
    bytes[] memory params = new bytes[](3);
    params[0] = abi.encode(tokenId, uint256(liquidityToAdd), uint128(amount0), uint128(amount1), bytes(""));
    params[1] = abi.encode(token0);
    params[2] = abi.encode(token1);

    pm.modifyLiquidities(abi.encode(actions, params), block.timestamp);

    if (amount0 > 0) {
      IAllowanceTransfer(permit2Addr).approve(token0, posm, 0, 0);
      IERC20(token0).safeApprove(permit2Addr, 0);
    }
    if (amount1 > 0) {
      IAllowanceTransfer(permit2Addr).approve(token1, posm, 0, 0);
      IERC20(token1).safeApprove(permit2Addr, 0);
    }

    if (slippageBps > 0) {
      uint256 used0 = balance0Before - IERC20(token0).balanceOf(address(this));
      uint256 used1 = balance1Before - IERC20(token1).balanceOf(address(this));
      require(
        used0 >= FullMath.mulDiv(expected0, 10_000 - slippageBps, 10_000)
          && used1 >= FullMath.mulDiv(expected1, 10_000 - slippageBps, 10_000),
        ISharedCommon.InsufficientOutput()
      );
    }
  }

  function collectFees(address posm, uint256 tokenId, ICommon.FeeConfig memory fc) external {
    _collectFees(posm, tokenId, fc);
  }

  function executeCalldata(address swapRouter, address posm, uint256 tokenId, bytes memory params) external {
    ISharedPancakeV4Utils.Instructions memory instructions = _decodeV4ExecuteCalldata(params, posm, tokenId);
    _executeInstruction(swapRouter, posm, tokenId, instructions);
  }

  function executeInstructionBytes(address swapRouter, address posm, uint256 tokenId, bytes memory instruction)
    external
  {
    ISharedPancakeV4Utils.Instructions memory instructions =
      abi.decode(instruction, (ISharedPancakeV4Utils.Instructions));
    _executeInstruction(swapRouter, posm, tokenId, instructions);
  }

  function swapAndMintCalldata(address swapRouter, address posm, bytes memory params) external {
    ISharedPancakeV4Utils.SwapAndMintParams memory mintParams = _decodeV4SwapAndMintCalldata(params, posm);
    _executeSwapAndMint(swapRouter, posm, mintParams);
  }

  function swapAndIncreaseCalldata(address swapRouter, address posm, uint256 tokenId, bytes memory params) external {
    ISharedPancakeV4Utils.SwapAndIncreaseParams memory increaseParams =
      _decodeV4SwapAndIncreaseCalldata(params, posm, tokenId);
    _executeSwapAndIncrease(swapRouter, posm, tokenId, increaseParams);
  }

  function exitProportional(
    address posm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1
  ) external returns (ISharedStrategy.PositionChange[] memory changes) {
    _requireWhitelistedPosm(posm);

    ICLPositionManager pm = ICLPositionManager(posm);
    uint128 posLiquidity = pm.getPositionLiquidity(tokenId);

    if (posLiquidity == 0) {
      (PoolKey memory zeroLiquidityKey,) = pm.getPoolAndPositionInfo(tokenId);
      changes = new ISharedStrategy.PositionChange[](1);
      changes[0] = ISharedStrategy.PositionChange(
        false, posm, tokenId, Currency.unwrap(zeroLiquidityKey.currency0), Currency.unwrap(zeroLiquidityKey.currency1)
      );
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) return new ISharedStrategy.PositionChange[](0);

    bool isFullExit = liquidityToRemove >= posLiquidity;

    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    _decreaseV4Principal(posm, poolKey, tokenId, liquidityToRemove, minAmount0, minAmount1, "", 0, block.timestamp);

    if (isFullExit) {
      changes = new ISharedStrategy.PositionChange[](1);
      changes[0] = ISharedStrategy.PositionChange(
        false, posm, tokenId, Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1)
      );
    } else {
      changes = new ISharedStrategy.PositionChange[](0);
    }
  }

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

  function _collectFees(address posm, uint256 tokenId, ICommon.FeeConfig memory fc) private {
    ICLPositionManager pm = ICLPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);

    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions =
      abi.encodePacked(uint8(PancakeV4Actions.DECREASE_LIQUIDITY), uint8(PancakeV4Actions.TAKE_PAIR));
    bytes[] memory collectParams = new bytes[](2);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), bytes(""));
    collectParams[1] = abi.encode(token0, token1, address(this));

    // The fee-sync collect (DECREASE_LIQUIDITY(0)+TAKE_PAIR) routes through the pool's remove-liquidity
    // hooks. If a fragile/hostile hook reverts, tolerate it ONLY when the position has no uncollected fees:
    // there is then nothing to distribute, so skipping cannot let a withdrawer over-sweep, and one such
    // position cannot brick SharedVault.withdraw (which requires collectFees to succeed for every position).
    // If fees ARE present, propagate the original revert so the fee-fairness guarantee is preserved.
    try pm.modifyLiquidities(abi.encode(actions, collectParams), block.timestamp) {
      uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
      uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
      if (collected0 == 0 && collected1 == 0) return;
      SharedStrategyFees.applyFees(token0, collected0, token1, collected1, fc);
    } catch (bytes memory reason) {
      if (_hasCollectableFeesForFailedCollect(posm, tokenId)) {
        assembly ("memory-safe") {
          revert(add(reason, 0x20), mload(reason))
        }
      }
    }
  }

  function _executeSwapAndMint(address swapRouter, address posm, ISharedPancakeV4Utils.SwapAndMintParams memory params)
    private
  {
    require(params.posm == posm, ISharedCommon.InvalidOperation());
    // F19: pin the caller-supplied pool manager (used as the pricing source for the mint) to the
    // POSM's own CL pool manager, so price cannot be read from an attacker-chosen manager.
    require(
      address(params.poolKey.poolManager) == address(ICLPositionManager(posm).clPoolManager()),
      ISharedCommon.InvalidOperation()
    );
    address token0 = Currency.unwrap(params.poolKey.currency0);
    address token1 = Currency.unwrap(params.poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);
    _validateV4InputTokens(params.inputTokens, token0, token1);

    (uint256 amount0, uint256 amount1) =
      _takeInputGasFeesAndGetPoolAmounts(token0, token1, params.inputTokens, params.gasFeeX64);
    (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, params.swapParams);
    _mintV4WithAmounts(posm, params.poolKey, amount0, amount1, params.mintParams);
  }

  function _executeSwapAndIncrease(
    address swapRouter,
    address posm,
    uint256 tokenId,
    ISharedPancakeV4Utils.SwapAndIncreaseParams memory params
  ) private {
    require(params.posm == posm && params.tokenId == tokenId, ISharedCommon.InvalidOperation());
    require(IERC721(posm).ownerOf(tokenId) == address(this), ISharedStrategy.InvalidPoolTokens());
    ICLPositionManager pm = ICLPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);
    _validateV4InputTokens(params.inputTokens, token0, token1);

    (uint256 amount0, uint256 amount1) =
      _takeInputGasFeesAndGetPoolAmounts(token0, token1, params.inputTokens, params.gasFeeX64);
    (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, params.swapParams);
    _increaseV4WithAmounts(posm, tokenId, poolKey, amount0, amount1, params.increaseParams);
  }

  function _executeInstruction(
    address swapRouter,
    address posm,
    uint256 tokenId,
    ISharedPancakeV4Utils.Instructions memory instructions
  ) private {
    ICLPositionManager pm = ICLPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);

    if (instructions.action == ISharedPancakeV4Utils.UtilActions.COMPOUND) {
      ISharedPancakeV4Utils.CompoundFeesParams memory compoundParams =
        abi.decode(instructions.params, (ISharedPancakeV4Utils.CompoundFeesParams));
      (uint256 amount0, uint256 amount1) =
        _collectV4GeneratedFees(posm, tokenId, poolKey, compoundParams.collectFeesHookData, compoundParams.gasFeeX64);
      (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, compoundParams.swapParams);
      _increaseV4WithAmounts(posm, tokenId, poolKey, amount0, amount1, compoundParams.increaseParams);
    } else if (instructions.action == ISharedPancakeV4Utils.UtilActions.DECREASE_AND_SWAP) {
      ISharedPancakeV4Utils.DecreaseAndSwapParams memory decParams =
        abi.decode(instructions.params, (ISharedPancakeV4Utils.DecreaseAndSwapParams));
      (uint256 amount0, uint256 amount1) =
        _collectV4GeneratedFees(posm, tokenId, poolKey, decParams.decreaseParams.hookData, decParams.gasFeeX64);
      (uint256 principal0, uint256 principal1) = _decreaseV4Principal(
        posm,
        poolKey,
        tokenId,
        decParams.decreaseParams.liquidity,
        decParams.decreaseParams.amount0Min,
        decParams.decreaseParams.amount1Min,
        decParams.decreaseParams.hookData,
        decParams.gasFeeX64,
        decParams.decreaseParams.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      // Decrease-and-exit: pool tokens are vault-tracked, so the post-pipeline totals do not need
      // to be threaded further. The pipeline still enforces full consumption of any non-pool
      // intermediates via the virtual ledger inside `_executeV4Swaps`.
      _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, decParams.swapParams);
    } else if (instructions.action == ISharedPancakeV4Utils.UtilActions.ADJUST_RANGE) {
      ISharedPancakeV4Utils.AdjustRangeParams memory adjustParams =
        abi.decode(instructions.params, (ISharedPancakeV4Utils.AdjustRangeParams));
      (uint256 amount0, uint256 amount1) =
        _collectV4GeneratedFees(posm, tokenId, poolKey, adjustParams.collectFeesHookData, adjustParams.gasFeeX64);
      uint128 liquidity = pm.getPositionLiquidity(tokenId);
      // F8: the old position's full-liquidity burn passes 0/0 minimums here because the rebalance
      // round-trip is bounded by `mintParams.minLiquidity` on the re-mint below — if a sandwich
      // drains value during the burn/swap, the post-swap proceeds cannot reach `minLiquidity` and
      // the whole operation reverts in `_mintV4WithAmounts`. A separate decrease-side floor would
      // be redundant, so `decreaseAmount0Min/1Min` were removed from `AdjustRangeParams`.
      (uint256 principal0, uint256 principal1) = _decreaseV4Principal(
        posm, poolKey, tokenId, liquidity, 0, 0, "", adjustParams.gasFeeX64, adjustParams.mintParams.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, adjustParams.swapParams);
      _mintV4WithAmounts(posm, poolKey, amount0, amount1, adjustParams.mintParams);
    } else {
      revert ISharedCommon.InvalidOperation();
    }
  }

  function _collectV4GeneratedFees(
    address posm,
    uint256 tokenId,
    PoolKey memory poolKey,
    bytes memory hookData,
    uint64 gasFeeX64
  ) private returns (uint256 net0, uint256 net1) {
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions =
      abi.encodePacked(uint8(PancakeV4Actions.DECREASE_LIQUIDITY), uint8(PancakeV4Actions.TAKE_PAIR));
    bytes[] memory collectParams = new bytes[](2);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), hookData);
    collectParams[1] = abi.encode(token0, token1, address(this));
    ICLPositionManager(posm).modifyLiquidities(abi.encode(actions, collectParams), block.timestamp);

    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (collected0 == 0 && collected1 == 0) return (0, 0);

    ICommon.FeeConfig memory fc = SharedStrategyFeeConfig.performanceFeeConfig();
    if (gasFeeX64 > 0) {
      fc.gasFeeX64 = gasFeeX64;
      fc.gasFeeRecipient = msg.sender;
    }
    (uint256 fee0, uint256 fee1) = SharedStrategyFees.applyFees(token0, collected0, token1, collected1, fc);
    net0 = collected0 - fee0;
    net1 = collected1 - fee1;
  }

  function _decreaseV4Principal(
    address posm,
    PoolKey memory poolKey,
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    bytes memory hookData,
    uint64 gasFeeX64,
    uint256 deadline
  ) private returns (uint256 net0, uint256 net1) {
    if (liquidity == 0) return (0, 0);
    ICLPositionManager pm = ICLPositionManager(posm);
    uint128 posLiquidity = pm.getPositionLiquidity(tokenId);
    if (liquidity > posLiquidity) liquidity = posLiquidity;

    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions =
      abi.encodePacked(uint8(PancakeV4Actions.DECREASE_LIQUIDITY), uint8(PancakeV4Actions.TAKE_PAIR));
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
    params[1] = abi.encode(token0, token1, address(this));
    pm.modifyLiquidities(abi.encode(actions, params), deadline == 0 ? block.timestamp : deadline);

    uint256 principal0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 principal1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (gasFeeX64 == 0 || (principal0 == 0 && principal1 == 0)) return (principal0, principal1);

    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: msg.sender
    });
    (uint256 fee0, uint256 fee1) = SharedStrategyFees.applyFees(token0, principal0, token1, principal1, gasOnly);
    net0 = principal0 - fee0;
    net1 = principal1 - fee1;
  }

  function _increaseV4WithAmounts(
    address posm,
    uint256 tokenId,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.IncreaseLiquidityParams memory params
  ) private {
    if (amount0 == 0 && amount1 == 0) return;
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    ICLPositionManager pm = ICLPositionManager(posm);
    (, CLPositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    (uint160 sqrtPriceX96,,,) = ICLPoolManager(address(poolKey.poolManager)).getSlot0(poolKey.toId());
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtPriceAtTick(positionInfo.tickLower()),
      TickMath.getSqrtPriceAtTick(positionInfo.tickUpper()),
      amount0,
      amount1
    );
    require(liquidity >= params.minLiquidity, ISharedCommon.InsufficientOutput());
    if (liquidity == 0) return;

    _approveV4PositionManager(posm, poolKey, amount0, amount1);
    bytes memory actions = abi.encodePacked(
      uint8(PancakeV4Actions.INCREASE_LIQUIDITY),
      uint8(PancakeV4Actions.CLOSE_CURRENCY),
      uint8(PancakeV4Actions.CLOSE_CURRENCY)
    );
    bytes[] memory callParams = new bytes[](3);
    callParams[0] = abi.encode(tokenId, uint256(liquidity), uint128(amount0), uint128(amount1), params.hookData);
    callParams[1] = abi.encode(Currency.unwrap(poolKey.currency0));
    callParams[2] = abi.encode(Currency.unwrap(poolKey.currency1));
    pm.modifyLiquidities(abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _mintV4WithAmounts(
    address posm,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.MintParams memory params
  ) private returns (uint256 tokenId) {
    if (amount0 == 0 && amount1 == 0) revert ISharedCommon.InvalidAmount();
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    ICLPositionManager pm = ICLPositionManager(posm);
    (uint160 sqrtPriceX96,,,) = ICLPoolManager(address(poolKey.poolManager)).getSlot0(poolKey.toId());
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtPriceAtTick(params.tickLower),
      TickMath.getSqrtPriceAtTick(params.tickUpper),
      amount0,
      amount1
    );
    require(liquidity >= params.minLiquidity && liquidity > 0, ISharedCommon.InsufficientOutput());

    tokenId = pm.nextTokenId();
    _approveV4PositionManager(posm, poolKey, amount0, amount1);
    bytes memory actions = abi.encodePacked(uint8(PancakeV4Actions.MINT_POSITION), uint8(PancakeV4Actions.SETTLE_PAIR));
    bytes[] memory callParams = new bytes[](2);
    callParams[0] = abi.encode(
      poolKey,
      params.tickLower,
      params.tickUpper,
      liquidity,
      uint128(amount0),
      uint128(amount1),
      address(this),
      params.hookData
    );
    callParams[1] = abi.encode(Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1));
    pm.modifyLiquidities(abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _executeV4Swaps(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams
  ) private returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;

    // Defense-in-depth: re-validate the immutable swap router against the live ConfigManager whitelist
    // (see SharedV4StrategyLib._executeV4Swaps), so the owner can revoke a bad aggregator at runtime.
    if (swapParams.length > 0) {
      require(
        ISharedVault(address(this)).configManager().isWhitelistedSwapRouter(swapRouter),
        ISharedCommon.InvalidSwapRouter(swapRouter)
      );
    }

    // See `SharedV4StrategyLib._executeV4Swaps` for the full rationale of the virtual ledger.
    // Non-pool intermediates are fed only by prior hops' outputs (never by the vault's pre-existing
    // balance) and MUST be fully consumed by the end of the pipeline, so no untracked balance is
    // left in the vault.
    address[] memory intTokens = new address[](swapParams.length);
    uint256[] memory intBalances = new uint256[](swapParams.length);
    uint256 intCount;

    for (uint256 i; i < swapParams.length;) {
      ISharedPancakeV4Utils.SwapParams memory swapParam = swapParams[i];
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

  function _isV4SwapOutputAllowed(
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

  /// @dev See `SharedV4StrategyLib._swapV4`: intentionally omits `_validateVaultToken` for
  ///      intermediate `tokenIn`/`tokenOut` because the DAG validator only pins the first hop
  ///      input and last hop output to pool tokens, and `_executeV4Swaps`'s virtual ledger
  ///      enforces that any non-pool intermediate produced by an earlier hop is fully consumed by
  ///      a later one. The `swapRouter` is immutable and trusted to be well-behaved.
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
    // Reject a self-swap explicitly rather than relying on the balance-delta subtraction to underflow.
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

  function _approveV4PositionManager(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1) private {
    address permit2Addr = address(IPositionManagerPermit2(posm).permit2());
    if (amount0 > 0) {
      address token0 = Currency.unwrap(poolKey.currency0);
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0) {
      address token1 = Currency.unwrap(poolKey.currency1);
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }
  }

  function _clearV4PositionManagerApprovals(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1)
    private
  {
    address permit2Addr = address(IPositionManagerPermit2(posm).permit2());
    if (amount0 > 0) {
      address token0 = Currency.unwrap(poolKey.currency0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, 0, 0);
      IERC20(token0).safeApprove(permit2Addr, 0);
    }
    if (amount1 > 0) {
      address token1 = Currency.unwrap(poolKey.currency1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, 0, 0);
      IERC20(token1).safeApprove(permit2Addr, 0);
    }
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
    // parity with the never-reverting Uniswap-V4 sibling (`SharedV4StrategyLib._positionAmountsSplit`,
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

  /// @dev The failed-collect fallback is only a gate for whether to re-revert a hook failure. Use a
  ///      non-wrapping positive-delta check here so feeGrowthInside < feeGrowthInsideLast does not
  ///      look like near-uint256.max pending fees and brick an otherwise zero-fee position. Normal
  ///      valuation still uses `_feeOwed`'s modulo arithmetic to mirror Pancake CL fee accounting.
  function _hasCollectableFeesForFailedCollect(address posm, uint256 tokenId) private view returns (bool) {
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

  function _validateVaultToken(address token) private view {
    require(ISharedVault(address(this)).isVaultToken(token), ISharedStrategy.InvalidPoolTokens());
  }

  function _requireWhitelistedPosm(address posm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), posm);
  }

  /// @dev Every positive-amount input must be both a vault token AND one of the pool currencies.
  ///      The currency match is essential: without it, an authorized executor could include a
  ///      non-pool vault token (e.g. DAI in a WETH/USDC mint) with a nonzero `gasFeeX64` and have
  ///      `_takeInputGasFeesAndGetPoolAmounts` siphon `amount * gasFeeX64 / Q64` of that token to
  ///      `msg.sender` while the remainder dangles unused (never folded into `amount0`/`amount1`).
  ///      Zero-amount entries are tolerated (they're a no-op for both fee and pool accounting).
  function _validateV4InputTokens(
    ISharedPancakeV4Utils.InputTokenParams[] memory inputTokens,
    address currency0,
    address currency1
  ) private view {
    for (uint256 i; i < inputTokens.length;) {
      if (inputTokens[i].amount > 0) {
        address token = inputTokens[i].token;
        _validateVaultToken(token);
        require(token == currency0 || token == currency1, ISharedStrategy.InvalidPoolTokens());
      }
      unchecked {
        i++;
      }
    }
  }

  function _takeInputGasFeesAndGetPoolAmounts(
    address currency0,
    address currency1,
    ISharedPancakeV4Utils.InputTokenParams[] memory inputTokens,
    uint64 gasFeeX64
  ) private returns (uint256 amount0, uint256 amount1) {
    for (uint256 i; i < inputTokens.length;) {
      uint256 amount = inputTokens[i].amount;
      address token = inputTokens[i].token;
      if (amount > 0 && gasFeeX64 > 0) amount -= _applySingleTokenGasFee(token, amount, gasFeeX64);
      if (inputTokens[i].token == currency0) amount0 += amount;
      else if (inputTokens[i].token == currency1) amount1 += amount;
      unchecked {
        i++;
      }
    }
  }

  function _applySingleTokenGasFee(address token, uint256 amount, uint64 gasFeeX64) private returns (uint256 gasFee) {
    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: msg.sender
    });
    (gasFee,) = SharedStrategyFees.applyFees(token, amount, address(0), 0, gasOnly);
  }

  function _v4ParamsSelector(bytes memory params) private pure returns (bytes4 selector) {
    require(params.length >= 4, ISharedCommon.InvalidOperation());
    selector = bytes4(params);
  }

  function _v4ParamsBody(bytes memory params) private pure returns (bytes memory body) {
    require(params.length >= 4, ISharedCommon.InvalidOperation());
    body = new bytes(params.length - 4);
    for (uint256 j; j < body.length;) {
      body[j] = params[j + 4];
      unchecked {
        ++j;
      }
    }
  }

  function _decodeV4ExecuteCalldata(bytes memory params, address posm, uint256 tokenId)
    private
    pure
    returns (ISharedPancakeV4Utils.Instructions memory instructions)
  {
    require(_v4ParamsSelector(params) == ISharedPancakeV4Utils.execute.selector, ISharedCommon.InvalidOperation());
    bytes memory body = _v4ParamsBody(params);
    (address p, uint256 tid, ISharedPancakeV4Utils.Instructions memory decodedInstructions) =
      abi.decode(body, (address, uint256, ISharedPancakeV4Utils.Instructions));
    require(p == posm && tid == tokenId, ISharedCommon.InvalidOperation());
    instructions = decodedInstructions;
  }

  function _decodeV4SwapAndMintCalldata(bytes memory params, address posm)
    private
    pure
    returns (ISharedPancakeV4Utils.SwapAndMintParams memory decodedParams)
  {
    require(_v4ParamsSelector(params) == ISharedPancakeV4Utils.swapAndMint.selector, ISharedCommon.InvalidOperation());
    decodedParams = abi.decode(_v4ParamsBody(params), (ISharedPancakeV4Utils.SwapAndMintParams));
    require(decodedParams.posm == posm, ISharedCommon.InvalidOperation());
  }

  function _decodeV4SwapAndIncreaseCalldata(bytes memory params, address posm, uint256 tokenId)
    private
    pure
    returns (ISharedPancakeV4Utils.SwapAndIncreaseParams memory decodedParams)
  {
    require(
      _v4ParamsSelector(params) == ISharedPancakeV4Utils.swapAndIncrease.selector, ISharedCommon.InvalidOperation()
    );
    decodedParams = abi.decode(_v4ParamsBody(params), (ISharedPancakeV4Utils.SwapAndIncreaseParams));
    require(decodedParams.posm == posm && decodedParams.tokenId == tokenId, ISharedCommon.InvalidOperation());
  }
}
