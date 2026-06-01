// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { Permit2Forwarder } from "@uniswap/v4-periphery/src/base/Permit2Forwarder.sol";
import { IPermit2Forwarder } from "@uniswap/v4-periphery/src/interfaces/IPermit2Forwarder.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { ISharedV4Utils } from "../interfaces/ISharedV4Utils.sol";
import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { IFeeTaker } from "../../public-vault/interfaces/strategies/IFeeTaker.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";

library SharedV4StrategyLib {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;
  using PoolIdLibrary for PoolKey;
  using PositionInfoLibrary for PositionInfo;
  using StateLibrary for IPoolManager;

  uint256 private constant Q64 = 0x10000000000000000;

  event FeeCollected(
    address indexed vaultAddress,
    IFeeTaker.FeeType indexed feeType,
    address indexed recipient,
    address token,
    uint256 amount
  );

  /// @dev Slippage model: the previous implementation requested EXACTLY `liquidityToAdd` and then
  ///      checked `liquidityAdded >= liquidityToAdd * (1 - bps)` — always true, so it provided no
  ///      protection. This version enforces a real per-token floor on the amounts ACTUALLY consumed
  ///      (measured via balance deltas) against the amounts quoted for `liquidityToAdd` at the
  ///      current price, with the `slippageBps` haircut. The floor is computed from
  ///      `getAmountsForLiquidity` (not the raw supplied `amount0/amount1`) so single-sided /
  ///      out-of-range positions — where one side is legitimately ~0 — do not spuriously revert.
  ///      NOTE: adding CL liquidity does not move the pool price, so within one tx `used == expected`;
  ///      this floor catches a misbehaving/non-canonical position manager but cannot by itself defeat
  ///      a CROSS-transaction spot-price sandwich. Callers must pass a conservative `slippageBps` and,
  ///      where MEV is a concern, derive the deposit ratio from an external price reference.
  function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps)
    external
  {
    if (amount0 == 0 && amount1 == 0) return;

    _requireWhitelistedPosm(posm);

    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, PositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    Currency currency0 = poolKey.currency0;
    Currency currency1 = poolKey.currency1;
    address token0 = Currency.unwrap(currency0);
    address token1 = Currency.unwrap(currency1);

    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());

    (uint160 sqrtPriceX96,,,) = pm.poolManager().getSlot0(poolKey.toId());
    uint160 sqrtLower = TickMath.getSqrtPriceAtTick(positionInfo.tickLower());
    uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(positionInfo.tickUpper());
    uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
    if (liquidityToAdd == 0) return;

    // Quote the token amounts this liquidity should consume at the current price; the real per-token
    // floor below is checked against these (never against the raw supplied amounts).
    (uint256 expected0, uint256 expected1) =
      LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtLower, sqrtUpper, liquidityToAdd);

    uint256 balance0Before = IERC20(token0).balanceOf(address(this));
    uint256 balance1Before = IERC20(token1).balanceOf(address(this));

    address permit2Addr = address(Permit2Forwarder(address(IPermit2Forwarder(posm))).permit2());
    if (amount0 > 0) {
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0) {
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }

    bytes memory actions =
      abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY));
    bytes[] memory params = new bytes[](3);
    params[0] = abi.encode(tokenId, uint256(liquidityToAdd), uint128(amount0), uint128(amount1), bytes(""));
    params[1] = abi.encode(currency0);
    params[2] = abi.encode(currency1);

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
    ISharedV4Utils.Instructions memory instructions = _decodeV4ExecuteCalldata(params, posm, tokenId);
    _executeInstruction(swapRouter, posm, tokenId, instructions);
  }

  function executeInstructionBytes(address swapRouter, address posm, uint256 tokenId, bytes memory instruction)
    external
  {
    ISharedV4Utils.Instructions memory instructions = abi.decode(instruction, (ISharedV4Utils.Instructions));
    _executeInstruction(swapRouter, posm, tokenId, instructions);
  }

  function swapAndMintCalldata(address swapRouter, address posm, bytes memory params) external {
    ISharedV4Utils.SwapAndMintParams memory mintParams = _decodeV4SwapAndMintCalldata(params, posm);
    _executeSwapAndMint(swapRouter, posm, mintParams);
  }

  function swapAndIncreaseCalldata(address swapRouter, address posm, uint256 tokenId, bytes memory params) external {
    ISharedV4Utils.SwapAndIncreaseParams memory increaseParams = _decodeV4SwapAndIncreaseCalldata(params, posm, tokenId);
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

    IPositionManager pm = IPositionManager(posm);
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
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);

    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
    bytes[] memory collectParams = new bytes[](2);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), bytes(""));
    collectParams[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));

    // The fee-sync collect (DECREASE_LIQUIDITY(0)+TAKE_PAIR) routes through the pool's remove-liquidity
    // hooks. If a fragile/hostile hook reverts, tolerate it ONLY when the position has no uncollected fees:
    // there is then nothing to distribute, so skipping cannot let a withdrawer over-sweep, and one such
    // position cannot brick SharedVault.withdraw (which requires collectFees to succeed for every position).
    // If fees ARE present, propagate the original revert so the fee-fairness guarantee is preserved.
    try pm.modifyLiquidities(abi.encode(actions, collectParams), block.timestamp) {
      uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
      uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
      if (collected0 == 0 && collected1 == 0) return;
      _applyFees(token0, collected0, token1, collected1, fc);
    } catch (bytes memory reason) {
      (,, uint256 pendingFee0, uint256 pendingFee1) = _positionAmountsSplit(posm, tokenId);
      if (pendingFee0 != 0 || pendingFee1 != 0) {
        assembly ("memory-safe") {
          revert(add(reason, 0x20), mload(reason))
        }
      }
    }
  }

  /// @dev Fees are applied SEQUENTIALLY against a running remainder: platform first, then owner, then
  ///      gas, and each fee is clamped to whatever is left (`if (fee > remaining) fee = remaining`).
  ///      Because every share is computed from the ORIGINAL `amount0/amount1` (not the running
  ///      remainder), the clamp only ever caps the LAST fee type(s) if the configured bps sum exceeds
  ///      100% — the total fee can never exceed the collected amount. On the withdraw `collectFees`
  ///      path this is inert (`performanceFeeConfig` sets gasFeeX64=0 and guarantees
  ///      platformBps+ownerBps<=10_000); it matters only when an operator-supplied `gasFeeX64` stacks
  ///      on top of platform/owner fees in the compound/decrease paths.
  function _applyFees(address token0, uint256 amount0, address token1, uint256 amount1, ICommon.FeeConfig memory fc)
    private
    returns (uint256 feeTaken0, uint256 feeTaken1)
  {
    uint256 remaining0 = amount0;
    uint256 remaining1 = amount1;

    if (fc.platformFeeBasisPoint > 0 && fc.platformFeeRecipient != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.platformFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.platformFeeBasisPoint, 10_000);
      if (fee0 > remaining0) fee0 = remaining0;
      if (fee1 > remaining1) fee1 = remaining1;
      if (fee0 > 0) _transferV4Fee(IFeeTaker.FeeType.PLATFORM, fc.platformFeeRecipient, token0, fee0);
      if (fee1 > 0) _transferV4Fee(IFeeTaker.FeeType.PLATFORM, fc.platformFeeRecipient, token1, fee1);
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
      if (fee0 > 0) _transferV4Fee(IFeeTaker.FeeType.OWNER, fc.vaultOwner, token0, fee0);
      if (fee1 > 0) _transferV4Fee(IFeeTaker.FeeType.OWNER, fc.vaultOwner, token1, fee1);
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
      if (fee0 > 0) _transferV4Fee(IFeeTaker.FeeType.GAS, fc.gasFeeRecipient, token0, fee0);
      if (fee1 > 0) _transferV4Fee(IFeeTaker.FeeType.GAS, fc.gasFeeRecipient, token1, fee1);
      feeTaken0 += fee0;
      feeTaken1 += fee1;
    }
  }

  function _transferV4Fee(IFeeTaker.FeeType feeType, address recipient, address token, uint256 amount) private {
    IERC20(token).safeTransfer(recipient, amount);
    emit FeeCollected(address(this), feeType, recipient, token, amount);
  }

  function _executeSwapAndMint(address swapRouter, address posm, ISharedV4Utils.SwapAndMintParams memory params)
    private
  {
    require(params.posm == posm, ISharedCommon.InvalidOperation());
    address token0 = Currency.unwrap(params.poolKey.currency0);
    address token1 = Currency.unwrap(params.poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);
    _validateV4InputTokens(params.inputTokens, params.poolKey.currency0, params.poolKey.currency1);

    (uint256 amount0, uint256 amount1) = _takeInputGasFeesAndGetPoolAmounts(
      params.poolKey.currency0, params.poolKey.currency1, params.inputTokens, params.gasFeeX64
    );
    (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, params.swapParams);
    _mintV4WithAmounts(posm, params.poolKey, amount0, amount1, params.mintParams);
  }

  function _executeSwapAndIncrease(
    address swapRouter,
    address posm,
    uint256 tokenId,
    ISharedV4Utils.SwapAndIncreaseParams memory params
  ) private {
    require(params.posm == posm && params.tokenId == tokenId, ISharedCommon.InvalidOperation());
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);
    _validateV4InputTokens(params.inputTokens, poolKey.currency0, poolKey.currency1);

    (uint256 amount0, uint256 amount1) =
      _takeInputGasFeesAndGetPoolAmounts(poolKey.currency0, poolKey.currency1, params.inputTokens, params.gasFeeX64);
    (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, params.swapParams);
    _increaseV4WithAmounts(posm, tokenId, poolKey, amount0, amount1, params.increaseParams);
  }

  function _executeInstruction(
    address swapRouter,
    address posm,
    uint256 tokenId,
    ISharedV4Utils.Instructions memory instructions
  ) private {
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);

    if (instructions.action == ISharedV4Utils.UtilActions.COMPOUND) {
      ISharedV4Utils.CompoundFeesParams memory compoundParams =
        abi.decode(instructions.params, (ISharedV4Utils.CompoundFeesParams));
      (uint256 amount0, uint256 amount1) =
        _collectV4GeneratedFees(posm, tokenId, poolKey, compoundParams.collectFeesHookData, compoundParams.gasFeeX64);
      (amount0, amount1) = _executeV4Swaps(swapRouter, token0, token1, amount0, amount1, compoundParams.swapParams);
      _increaseV4WithAmounts(posm, tokenId, poolKey, amount0, amount1, compoundParams.increaseParams);
    } else if (instructions.action == ISharedV4Utils.UtilActions.DECREASE_AND_SWAP) {
      ISharedV4Utils.DecreaseAndSwapParams memory decParams =
        abi.decode(instructions.params, (ISharedV4Utils.DecreaseAndSwapParams));
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
    } else if (instructions.action == ISharedV4Utils.UtilActions.ADJUST_RANGE) {
      ISharedV4Utils.AdjustRangeParams memory adjustParams =
        abi.decode(instructions.params, (ISharedV4Utils.AdjustRangeParams));
      (uint256 amount0, uint256 amount1) =
        _collectV4GeneratedFees(posm, tokenId, poolKey, adjustParams.collectFeesHookData, adjustParams.gasFeeX64);
      uint128 liquidity = pm.getPositionLiquidity(tokenId);
      // F8: the old position's full-liquidity burn passes 0/0 minimums here because the rebalance
      // round-trip is bounded by `mintParams.minLiquidity` on the re-mint below — if a sandwich
      // drains value during the burn/swap, the post-swap proceeds cannot reach `minLiquidity` and
      // the whole operation reverts in `_mintV4WithAmounts`. A separate decrease-side floor would
      // be redundant, so `decreaseAmount0Min/1Min` were removed from `AdjustRangeParams`.
      (uint256 principal0, uint256 principal1) = _decreaseV4Principal(
        posm,
        poolKey,
        tokenId,
        liquidity,
        0,
        0,
        "",
        adjustParams.gasFeeX64,
        adjustParams.mintParams.deadline
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

    bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
    bytes[] memory collectParams = new bytes[](2);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), hookData);
    collectParams[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    IPositionManager(posm).modifyLiquidities(abi.encode(actions, collectParams), block.timestamp);

    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (collected0 == 0 && collected1 == 0) return (0, 0);

    ICommon.FeeConfig memory fc = SharedStrategyFeeConfig.performanceFeeConfig();
    if (gasFeeX64 > 0) {
      fc.gasFeeX64 = gasFeeX64;
      fc.gasFeeRecipient = msg.sender;
    }
    (uint256 fee0, uint256 fee1) = _applyFees(token0, collected0, token1, collected1, fc);
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
    IPositionManager pm = IPositionManager(posm);
    uint128 posLiquidity = pm.getPositionLiquidity(tokenId);
    if (liquidity > posLiquidity) liquidity = posLiquidity;

    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
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
    (uint256 fee0, uint256 fee1) = _applyFees(token0, principal0, token1, principal1, gasOnly);
    net0 = principal0 - fee0;
    net1 = principal1 - fee1;
  }

  function _increaseV4WithAmounts(
    address posm,
    uint256 tokenId,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.IncreaseLiquidityParams memory params
  ) private {
    if (amount0 == 0 && amount1 == 0) return;
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    IPositionManager pm = IPositionManager(posm);
    PositionInfo positionInfo = pm.positionInfo(tokenId);
    (uint160 sqrtPriceX96,,,) = pm.poolManager().getSlot0(poolKey.toId());
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
      uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
    );
    bytes[] memory callParams = new bytes[](3);
    callParams[0] = abi.encode(tokenId, uint256(liquidity), uint128(amount0), uint128(amount1), params.hookData);
    callParams[1] = abi.encode(poolKey.currency0);
    callParams[2] = abi.encode(poolKey.currency1);
    pm.modifyLiquidities(abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _mintV4WithAmounts(
    address posm,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.MintParams memory params
  ) private returns (uint256 tokenId) {
    if (amount0 == 0 && amount1 == 0) revert ISharedCommon.InvalidAmount();
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    IPositionManager pm = IPositionManager(posm);
    (uint160 sqrtPriceX96,,,) = pm.poolManager().getSlot0(poolKey.toId());
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
    bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
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
    callParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
    pm.modifyLiquidities(abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  /// @dev Executes the swap DAG and returns the running pool-token balances.
  ///      Non-pool intermediate tokens are tracked in a virtual ledger that is fed exclusively by
  ///      outputs of prior hops in this pipeline — never by the vault's pre-existing balance.
  ///      After the pipeline, every intermediate entry MUST equal zero (i.e. fully consumed back
  ///      to the pool tokens). This prevents:
  ///        (a) leakage of unrelated vault holdings into the swap pipeline via `balanceOf(this)`, and
  ///        (b) leftover non-pool tokens being silently left in the vault outside of TVL/share
  ///            accounting (non-pool tokens are not vault tokens, so any residue is untracked).
  ///      Operators can pass `amountIn == 0` on an intermediate hop to consume the entire tracked
  ///      balance produced by prior hops.
  function _executeV4Swaps(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.SwapParams[] memory swapParams
  ) private returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;

    // Defense-in-depth: re-validate the immutable swap router against the live ConfigManager whitelist
    // at execution time, so the owner can revoke a compromised/deprecated aggregator as a kill-switch
    // (the vault-level CALL path performs the same check). Only when the pipeline actually swaps.
    if (swapParams.length > 0) {
      require(
        ISharedVault(address(this)).configManager().isWhitelistedSwapRouter(swapRouter),
        ISharedCommon.InvalidSwapRouter(swapRouter)
      );
    }

    // Virtual ledger of non-pool intermediate tokens produced/consumed inside this pipeline.
    // Sized to swapParams.length: each entry can only enter the ledger via a hop's `tokenOut`,
    // and there are at most `swapParams.length` such outputs.
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
        swapRouter, swapParam.tokenIn, swapParam.tokenOut, amountIn, swapParam.amountOutMin, swapParam.swapData
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

    // Every non-pool intermediate produced by the pipeline must have been fully consumed by a
    // subsequent hop. Leftover intermediates would land in the vault outside TVL accounting.
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

  /// @dev Unlike `SharedV3Strategy._swap`, this does NOT call `_validateVaultToken(tokenIn/tokenOut)`.
  ///      V4 supports multi-hop DAGs where intermediate `tokenIn`/`tokenOut` can be any ERC20 (the
  ///      DAG validator only constrains the first hop input and last hop output to pool tokens).
  ///      Safety of non-vault intermediates is enforced by `_executeV4Swaps`'s virtual ledger,
  ///      which requires every intermediate to be fully consumed by the end of the pipeline so no
  ///      untracked balance is left behind in the vault. The `swapRouter` itself is immutable and
  ///      trusted to be well-behaved.
  function _swapV4(
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory swapData
  ) private returns (uint256 amountInDelta, uint256 amountOutDelta) {
    if (amountIn == 0 || swapData.length == 0 || tokenOut == address(0)) return (0, 0);
    // Reject a self-swap explicitly rather than relying on the balance-delta subtraction to underflow:
    // with tokenIn == tokenOut the in/out deltas reference the same balance and netting is meaningless.
    require(tokenIn != tokenOut, ISharedCommon.InvalidOperation());

    uint256 balanceInBefore = IERC20(tokenIn).balanceOf(address(this));
    uint256 balanceOutBefore = IERC20(tokenOut).balanceOf(address(this));
    IERC20(tokenIn).safeResetAndApprove(swapRouter, amountIn);
    (bool success,) = swapRouter.call(swapData);
    if (!success) revert ISharedCommon.SwapFailed();
    IERC20(tokenIn).safeApprove(swapRouter, 0);
    uint256 balanceInAfter = IERC20(tokenIn).balanceOf(address(this));
    uint256 balanceOutAfter = IERC20(tokenOut).balanceOf(address(this));

    amountInDelta = balanceInBefore - balanceInAfter;
    amountOutDelta = balanceOutAfter - balanceOutBefore;
    require(amountOutDelta >= amountOutMin, ISharedCommon.InsufficientOutput());
  }

  function _approveV4PositionManager(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1) private {
    address permit2Addr = address(Permit2Forwarder(address(IPermit2Forwarder(posm))).permit2());
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
    address permit2Addr = address(Permit2Forwarder(address(IPermit2Forwarder(posm))).permit2());
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
    ISharedV4Utils.InputTokenParams[] memory inputTokens,
    Currency currency0,
    Currency currency1
  ) private view {
    for (uint256 i; i < inputTokens.length;) {
      if (inputTokens[i].amount > 0) {
        Currency token = inputTokens[i].token;
        _validateVaultToken(Currency.unwrap(token));
        require(token == currency0 || token == currency1, ISharedStrategy.InvalidPoolTokens());
      }
      unchecked {
        i++;
      }
    }
  }

  function _takeInputGasFeesAndGetPoolAmounts(
    Currency currency0,
    Currency currency1,
    ISharedV4Utils.InputTokenParams[] memory inputTokens,
    uint64 gasFeeX64
  ) private returns (uint256 amount0, uint256 amount1) {
    for (uint256 i; i < inputTokens.length;) {
      uint256 amount = inputTokens[i].amount;
      address token = Currency.unwrap(inputTokens[i].token);
      if (amount > 0 && gasFeeX64 > 0) {
        uint256 gasFee = FullMath.mulDiv(amount, gasFeeX64, Q64);
        if (gasFee > amount) gasFee = amount;
        if (gasFee > 0) {
          _transferV4Fee(IFeeTaker.FeeType.GAS, msg.sender, token, gasFee);
          amount -= gasFee;
        }
      }
      if (inputTokens[i].token == currency0) amount0 += amount;
      else if (inputTokens[i].token == currency1) amount1 += amount;
      unchecked {
        i++;
      }
    }
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
    returns (ISharedV4Utils.Instructions memory instructions)
  {
    require(_v4ParamsSelector(params) == ISharedV4Utils.execute.selector, ISharedCommon.InvalidOperation());
    bytes memory body = _v4ParamsBody(params);
    (address p, uint256 tid, ISharedV4Utils.Instructions memory decodedInstructions) =
      abi.decode(body, (address, uint256, ISharedV4Utils.Instructions));
    require(p == posm && tid == tokenId, ISharedCommon.InvalidOperation());
    instructions = decodedInstructions;
  }

  function _decodeV4SwapAndMintCalldata(bytes memory params, address posm)
    private
    pure
    returns (ISharedV4Utils.SwapAndMintParams memory decodedParams)
  {
    require(_v4ParamsSelector(params) == ISharedV4Utils.swapAndMint.selector, ISharedCommon.InvalidOperation());
    decodedParams = abi.decode(_v4ParamsBody(params), (ISharedV4Utils.SwapAndMintParams));
    require(decodedParams.posm == posm, ISharedCommon.InvalidOperation());
  }

  function _decodeV4SwapAndIncreaseCalldata(bytes memory params, address posm, uint256 tokenId)
    private
    pure
    returns (ISharedV4Utils.SwapAndIncreaseParams memory decodedParams)
  {
    require(_v4ParamsSelector(params) == ISharedV4Utils.swapAndIncrease.selector, ISharedCommon.InvalidOperation());
    decodedParams = abi.decode(_v4ParamsBody(params), (ISharedV4Utils.SwapAndIncreaseParams));
    require(decodedParams.posm == posm && decodedParams.tokenId == tokenId, ISharedCommon.InvalidOperation());
  }
}
