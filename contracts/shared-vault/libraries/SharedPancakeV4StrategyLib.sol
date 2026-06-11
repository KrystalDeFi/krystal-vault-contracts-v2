// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
import { IWETH9 } from "../../public-vault/interfaces/IWETH9.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyFees } from "../libraries/SharedStrategyFees.sol";
import { SharedV4SwapPipeline } from "../libraries/SharedV4SwapPipeline.sol";
import { SharedPancakeV4ValuationLib } from "../libraries/SharedPancakeV4ValuationLib.sol";

import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { ICLPositionManager } from "infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";
import { IPositionManagerPermit2 } from "infinity-periphery/src/interfaces/IPositionManagerPermit2.sol";

library SharedPancakeV4StrategyLib {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;
  using CLPositionInfoLibrary for CLPositionInfo;

  uint8 private constant ACTION_INCREASE_LIQUIDITY = 0x00;
  uint8 private constant ACTION_DECREASE_LIQUIDITY = 0x01;
  uint8 private constant ACTION_MINT_POSITION = 0x02;
  uint8 private constant ACTION_SETTLE_PAIR = 0x0d;
  uint8 private constant ACTION_TAKE_PAIR = 0x11;
  uint8 private constant ACTION_CLOSE_CURRENCY = 0x12;
  uint8 private constant ACTION_SWEEP = 0x14;

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
    Currency currency0 = poolKey.currency0;
    Currency currency1 = poolKey.currency1;
    (address token0, address token1) = _validatePoolVaultTokens(currency0, currency1);

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
    if (amount0 > 0 && !_isNative(currency0)) {
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0 && !_isNative(currency1)) {
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }

    bool hasNative = _hasNative(poolKey);
    bytes memory actions = hasNative
      ? abi.encodePacked(
        uint8(ACTION_INCREASE_LIQUIDITY),
        uint8(ACTION_CLOSE_CURRENCY),
        uint8(ACTION_CLOSE_CURRENCY),
        uint8(ACTION_SWEEP)
      )
      : abi.encodePacked(uint8(ACTION_INCREASE_LIQUIDITY), uint8(ACTION_CLOSE_CURRENCY), uint8(ACTION_CLOSE_CURRENCY));
    bytes[] memory params = new bytes[](hasNative ? 4 : 3);
    params[0] = abi.encode(tokenId, uint256(liquidityToAdd), uint128(amount0), uint128(amount1), bytes(""));
    params[1] = abi.encode(currency0);
    params[2] = abi.encode(currency1);
    if (hasNative) params[3] = abi.encode(Currency.wrap(address(0)), address(this));

    uint256 nativeBefore = address(this).balance;
    uint256 nativeValue = _unwrapNativeForPool(poolKey, amount0, amount1);
    pm.modifyLiquidities{ value: nativeValue }(abi.encode(actions, params), block.timestamp);
    _wrapNativeBalanceDelta(nativeBefore);

    if (amount0 > 0 && !_isNative(currency0)) {
      IAllowanceTransfer(permit2Addr).approve(token0, posm, 0, 0);
      IERC20(token0).safeApprove(permit2Addr, 0);
    }
    if (amount1 > 0 && !_isNative(currency1)) {
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
      (address token0, address token1) = _poolVaultTokens(zeroLiquidityKey.currency0, zeroLiquidityKey.currency1);
      changes = new ISharedStrategy.PositionChange[](1);
      changes[0] = ISharedStrategy.PositionChange(false, posm, tokenId, token0, token1);
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) return new ISharedStrategy.PositionChange[](0);

    bool isFullExit = liquidityToRemove >= posLiquidity;

    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    _decreaseV4Principal(posm, poolKey, tokenId, liquidityToRemove, minAmount0, minAmount1, "", 0, block.timestamp);

    if (isFullExit) {
      (address token0, address token1) = _poolVaultTokens(poolKey.currency0, poolKey.currency1);
      changes = new ISharedStrategy.PositionChange[](1);
      changes[0] = ISharedStrategy.PositionChange(false, posm, tokenId, token0, token1);
    } else {
      changes = new ISharedStrategy.PositionChange[](0);
    }
  }

  // Position valuation (`getPositionAmounts` / `getPositionPrincipalAmounts` / `getPositionAmountsSplit`)
  // lives in `SharedPancakeV4ValuationLib`; callers (the strategy contract and tests) invoke it directly.
  // This keeps the strategy library under the EIP-170 deploy-size limit.

  function _collectFees(address posm, uint256 tokenId, ICommon.FeeConfig memory fc) private {
    ICLPositionManager pm = ICLPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    (address token0, address token1) = _poolVaultTokens(poolKey.currency0, poolKey.currency1);

    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(uint8(ACTION_DECREASE_LIQUIDITY), uint8(ACTION_TAKE_PAIR));
    bytes[] memory collectParams = new bytes[](2);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), bytes(""));
    collectParams[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));

    // The fee-sync collect (DECREASE_LIQUIDITY(0)+TAKE_PAIR) routes through the pool's remove-liquidity
    // hooks. If a fragile/hostile hook reverts, tolerate it ONLY when the position has no uncollected fees:
    // there is then nothing to distribute, so skipping cannot let a withdrawer over-sweep, and one such
    // position cannot brick SharedVault.withdraw (which requires collectFees to succeed for every position).
    // If fees ARE present, propagate the original revert so the fee-fairness guarantee is preserved.
    uint256 nativeBefore = address(this).balance;
    try pm.modifyLiquidities(abi.encode(actions, collectParams), block.timestamp) {
      _wrapNativeBalanceDelta(nativeBefore);
      uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
      uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
      if (collected0 == 0 && collected1 == 0) return;
      SharedStrategyFees.applyFees(token0, collected0, token1, collected1, fc);
    } catch (bytes memory reason) {
      if (SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(posm, tokenId)) {
        assembly ("memory-safe") {
          revert(add(reason, 0x20), mload(reason))
        }
      }
    }
  }

  // Input-token validation, the input gas-fee skim, and the non-pool-input ledger (the "fund the
  // LP from a third vault token" flow) all live in `SharedV4SwapPipeline.executePancakeWithInputs`
  // — the single audited input/swap boundary shared with the Uniswap V4 twin. Keeping them out of
  // this library also preserves its EIP-170 headroom.

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
    (address token0, address token1) = _validatePoolVaultTokens(params.poolKey.currency0, params.poolKey.currency1);
    (uint256 amount0, uint256 amount1) = SharedV4SwapPipeline.executePancakeWithInputs(
      swapRouter, token0, token1, params.inputTokens, params.gasFeeX64, params.swapParams
    );
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
    (address token0, address token1) = _validatePoolVaultTokens(poolKey.currency0, poolKey.currency1);
    (uint256 amount0, uint256 amount1) = SharedV4SwapPipeline.executePancakeWithInputs(
      swapRouter, token0, token1, params.inputTokens, params.gasFeeX64, params.swapParams
    );
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
    (address token0, address token1) = _validatePoolVaultTokens(poolKey.currency0, poolKey.currency1);

    if (instructions.action == ISharedPancakeV4Utils.UtilActions.COMPOUND) {
      ISharedPancakeV4Utils.CompoundFeesParams memory compoundParams =
        abi.decode(instructions.params, (ISharedPancakeV4Utils.CompoundFeesParams));
      (uint256 amount0, uint256 amount1) =
        _collectV4GeneratedFees(posm, tokenId, poolKey, compoundParams.collectFeesHookData, compoundParams.gasFeeX64);
      (amount0, amount1) =
        SharedV4SwapPipeline.executePancake(swapRouter, token0, token1, amount0, amount1, compoundParams.swapParams);
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
      // Decrease-and-exit intentionally drops the returned token0/token1 totals: pool tokens stay
      // vault-tracked as idle balances. The pipeline still enforces full consumption of any non-pool
      // intermediates through its virtual ledger.
      SharedV4SwapPipeline.executePancake(swapRouter, token0, token1, amount0, amount1, decParams.swapParams);
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
      (amount0, amount1) =
        SharedV4SwapPipeline.executePancake(swapRouter, token0, token1, amount0, amount1, adjustParams.swapParams);
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
    (address token0, address token1) = _poolVaultTokens(poolKey.currency0, poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(uint8(ACTION_DECREASE_LIQUIDITY), uint8(ACTION_TAKE_PAIR));
    bytes[] memory collectParams = new bytes[](2);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), hookData);
    collectParams[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    uint256 nativeBefore = address(this).balance;
    ICLPositionManager(posm).modifyLiquidities(abi.encode(actions, collectParams), block.timestamp);
    _wrapNativeBalanceDelta(nativeBefore);

    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (collected0 == 0 && collected1 == 0) return (0, 0);

    ICommon.FeeConfig memory fc = SharedStrategyFeeConfig.performanceFeeConfig();
    if (gasFeeX64 > 0) {
      (gasFeeX64, fc.gasFeeRecipient) = SharedStrategyFeeConfig.validateGasFeeX64(gasFeeX64);
      fc.gasFeeX64 = gasFeeX64;
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

    (address token0, address token1) = _poolVaultTokens(poolKey.currency0, poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(uint8(ACTION_DECREASE_LIQUIDITY), uint8(ACTION_TAKE_PAIR));
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    uint256 nativeBefore = address(this).balance;
    pm.modifyLiquidities(abi.encode(actions, params), deadline == 0 ? block.timestamp : deadline);
    _wrapNativeBalanceDelta(nativeBefore);

    uint256 principal0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 principal1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (gasFeeX64 == 0 || (principal0 == 0 && principal1 == 0)) return (principal0, principal1);
    address gasFeeRecipient;
    (gasFeeX64, gasFeeRecipient) = SharedStrategyFeeConfig.validateGasFeeX64(gasFeeX64);

    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: gasFeeRecipient
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
    // Auto-gate (same invariant as _mintV4WithAmounts): swapAndIncrease/COMPOUND reach this
    // increase chokepoint for any vault-OWNED tokenId — vault-TRACKED is not required — so a
    // hooked-pool position planted on the vault (minted with recipient = vault) could otherwise
    // route vault funds through its add-liquidity hook. Tracked positions are provably hook-free
    // (gated at mint and at getPositionTokens on every tracking entry), so this can only fire for
    // planted NFTs. Sits after the zero-amount early-return so no-op compounds stay no-ops.
    SharedStrategyGuards.requireNoLiquidityHookCL(poolKey.parameters);
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
    bool hasNative = _hasNative(poolKey);
    bytes memory actions = hasNative
      ? abi.encodePacked(
        uint8(ACTION_INCREASE_LIQUIDITY),
        uint8(ACTION_CLOSE_CURRENCY),
        uint8(ACTION_CLOSE_CURRENCY),
        uint8(ACTION_SWEEP)
      )
      : abi.encodePacked(uint8(ACTION_INCREASE_LIQUIDITY), uint8(ACTION_CLOSE_CURRENCY), uint8(ACTION_CLOSE_CURRENCY));
    bytes[] memory callParams = new bytes[](hasNative ? 4 : 3);
    callParams[0] = abi.encode(tokenId, uint256(liquidity), uint128(amount0), uint128(amount1), params.hookData);
    callParams[1] = abi.encode(poolKey.currency0);
    callParams[2] = abi.encode(poolKey.currency1);
    if (hasNative) callParams[3] = abi.encode(Currency.wrap(address(0)), address(this));
    uint256 nativeBefore = address(this).balance;
    uint256 nativeValue = _unwrapNativeForPool(poolKey, amount0, amount1);
    pm.modifyLiquidities{ value: nativeValue }(
      abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline
    );
    _wrapNativeBalanceDelta(nativeBefore);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _mintV4WithAmounts(
    address posm,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.MintParams memory params
  ) private returns (uint256 tokenId) {
    // Auto-gate: refuse pools whose hook intercepts liquidity removal. The withdraw/adjust exit
    // paths remove with empty hookData; a remove-hook pool could revert there and freeze withdraws,
    // so such a position must never be minted/tracked. Single chokepoint for both swapAndMint and
    // the ADJUST_RANGE re-mint.
    SharedStrategyGuards.requireNoLiquidityHookCL(poolKey.parameters);
    if (amount0 == 0 && amount1 == 0) revert ISharedCommon.InvalidAmount();
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    ICLPositionManager pm = ICLPositionManager(posm);
    (uint160 sqrtPriceX96,,,) = ICLPoolManager(address(poolKey.poolManager)).getSlot0(poolKey.toId());
    // Pancake V4 PoolKey has no manager field; the POSM's immutable manager is authoritative here.
    require(sqrtPriceX96 != 0, ISharedCommon.InvalidOperation());
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
    bool hasNative = _hasNative(poolKey);
    bytes memory actions = hasNative
      ? abi.encodePacked(uint8(ACTION_MINT_POSITION), uint8(ACTION_SETTLE_PAIR), uint8(ACTION_SWEEP))
      : abi.encodePacked(uint8(ACTION_MINT_POSITION), uint8(ACTION_SETTLE_PAIR));
    bytes[] memory callParams = new bytes[](hasNative ? 3 : 2);
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
    callParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
    if (hasNative) callParams[2] = abi.encode(Currency.wrap(address(0)), address(this));
    uint256 nativeBefore = address(this).balance;
    uint256 nativeValue = _unwrapNativeForPool(poolKey, amount0, amount1);
    pm.modifyLiquidities{ value: nativeValue }(
      abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline
    );
    _wrapNativeBalanceDelta(nativeBefore);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _approveV4PositionManager(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1) private {
    address permit2Addr = address(IPositionManagerPermit2(posm).permit2());
    if (amount0 > 0 && !_isNative(poolKey.currency0)) {
      address token0 = Currency.unwrap(poolKey.currency0);
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0 && !_isNative(poolKey.currency1)) {
      address token1 = Currency.unwrap(poolKey.currency1);
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }
  }

  function _clearV4PositionManagerApprovals(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1)
    private
  {
    address permit2Addr = address(IPositionManagerPermit2(posm).permit2());
    if (amount0 > 0 && !_isNative(poolKey.currency0)) {
      address token0 = Currency.unwrap(poolKey.currency0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, 0, 0);
      IERC20(token0).safeApprove(permit2Addr, 0);
    }
    if (amount1 > 0 && !_isNative(poolKey.currency1)) {
      address token1 = Currency.unwrap(poolKey.currency1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, 0, 0);
      IERC20(token1).safeApprove(permit2Addr, 0);
    }
  }

  // The position valuation + fee-growth math (`_positionAmountsSplit`, `_getFeeGrowthInside`,
  // `_feeOwed`, `hasCollectableFeesForFailedCollect`, `_hasPositiveCollectFeeDelta`) was moved to
  // `SharedPancakeV4ValuationLib` to keep this library under the EIP-170 deploy-size limit.

  function _validateVaultToken(address token) private view {
    require(ISharedVault(address(this)).isVaultToken(token), ISharedStrategy.InvalidPoolTokens());
  }

  function _validatePoolVaultTokens(Currency currency0, Currency currency1)
    private
    view
    returns (address token0, address token1)
  {
    (token0, token1) = _poolVaultTokens(currency0, currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);
  }

  function _poolVaultTokens(Currency currency0, Currency currency1)
    private
    view
    returns (address token0, address token1)
  {
    token0 = _vaultToken(currency0);
    token1 = _vaultToken(currency1);
    require(token0 != token1, ISharedStrategy.InvalidPoolTokens());
  }

  function _vaultToken(Currency currency) private view returns (address token) {
    token = Currency.unwrap(currency);
    if (token == address(0)) token = ISharedVault(address(this)).weth();
  }

  function _isNative(Currency currency) private pure returns (bool) {
    return Currency.unwrap(currency) == address(0);
  }

  function _hasNative(PoolKey memory poolKey) private pure returns (bool) {
    return _isNative(poolKey.currency0) || _isNative(poolKey.currency1);
  }

  function _unwrapNativeForPool(PoolKey memory poolKey, uint256 amount0, uint256 amount1)
    private
    returns (uint256 nativeValue)
  {
    if (_isNative(poolKey.currency0)) nativeValue = amount0;
    else if (_isNative(poolKey.currency1)) nativeValue = amount1;
    if (nativeValue > 0) IWETH9(ISharedVault(address(this)).weth()).withdraw(nativeValue);
  }

  function _wrapNativeBalanceDelta(uint256 nativeBefore) private {
    uint256 nativeAfter = address(this).balance;
    if (nativeAfter > nativeBefore) {
      IWETH9(ISharedVault(address(this)).weth()).deposit{ value: nativeAfter - nativeBefore }();
    }
  }

  function _requireWhitelistedPosm(address posm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), posm);
  }

  function _v4ParamsSelector(bytes memory params) internal pure returns (bytes4 selector) {
    require(params.length >= 4, ISharedCommon.InvalidOperation());
    selector = bytes4(params);
  }

  /// @dev Returns `params` with its leading 4-byte selector stripped, as a FRESH buffer — the caller's
  ///      `params` is left byte-for-byte intact (unlike the former in-place variant that aliased
  ///      `params + 4` and clobbered its length word + selector). Allocated by hand rather than via
  ///      `new bytes` to skip the redundant zero-fill (mcopy overwrites it anyway), which keeps this
  ///      size-constrained library further under the EIP-170 limit. Mechanics:
  ///        - `body` := free-memory pointer; store the new length `len - 4` at `body`.
  ///        - mcopy the tail: source skips params' length word (0x20) and selector (0x04) => `params + 0x24`.
  ///        - advance the free pointer by 0x20 (length word) + data rounded up to a 32-byte word.
  ///      `mcopy` copies exactly `bodyLen` bytes, so non-word-aligned tails neither over-read `params` nor
  ///      over-write `body`. Covered by SharedV4ParamsDecode.t.sol (non-mutation, fuzz, unaligned, empty).
  function _v4ParamsBody(bytes memory params) internal pure returns (bytes memory body) {
    uint256 len = params.length;
    require(len >= 4, ISharedCommon.InvalidOperation());
    assembly ("memory-safe") {
      body := mload(0x40)
      let bodyLen := sub(len, 4)
      mstore(body, bodyLen)
      mcopy(add(body, 0x20), add(params, 0x24), bodyLen)
      mstore(0x40, add(body, and(add(bodyLen, 0x3f), not(0x1f))))
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
