// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyFees } from "../libraries/SharedStrategyFees.sol";
import { SharedV4SwapPipeline } from "../libraries/SharedV4SwapPipeline.sol";

library SharedV4StrategyLib {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;
  using PoolIdLibrary for PoolKey;
  using PositionInfoLibrary for PositionInfo;
  using StateLibrary for IPoolManager;

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
    uint128 liquidityToAdd =
      LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
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
      SharedStrategyFees.applyFees(token0, collected0, token1, collected1, fc);
    } catch (bytes memory reason) {
      if (_hasCollectableFeesForFailedCollect(posm, tokenId)) {
        assembly ("memory-safe") {
          revert(add(reason, 0x20), mload(reason))
        }
      }
    }
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
    (amount0, amount1) =
      SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, params.swapParams);
    _mintV4WithAmounts(posm, params.poolKey, amount0, amount1, params.mintParams);
  }

  function _executeSwapAndIncrease(
    address swapRouter,
    address posm,
    uint256 tokenId,
    ISharedV4Utils.SwapAndIncreaseParams memory params
  ) private {
    require(params.posm == posm && params.tokenId == tokenId, ISharedCommon.InvalidOperation());
    require(IERC721(posm).ownerOf(tokenId) == address(this), ISharedStrategy.InvalidPoolTokens());
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);
    _validateV4InputTokens(params.inputTokens, poolKey.currency0, poolKey.currency1);

    (uint256 amount0, uint256 amount1) =
      _takeInputGasFeesAndGetPoolAmounts(poolKey.currency0, poolKey.currency1, params.inputTokens, params.gasFeeX64);
    (amount0, amount1) =
      SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, params.swapParams);
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
      (amount0, amount1) =
        SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, compoundParams.swapParams);
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
      // Decrease-and-exit intentionally drops the returned token0/token1 totals: pool tokens stay
      // vault-tracked as idle balances. The pipeline still enforces full consumption of any non-pool
      // intermediates through its virtual ledger.
      SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, decParams.swapParams);
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
        posm, poolKey, tokenId, liquidity, 0, 0, "", adjustParams.gasFeeX64, adjustParams.mintParams.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      (amount0, amount1) =
        SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, adjustParams.swapParams);
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
    // Uniswap V4 PoolKey has no manager field; the POSM's immutable manager is authoritative here.
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

  /// @dev The failed-collect fallback is only a gate for whether to re-revert a hook failure. Use a
  ///      non-wrapping positive-delta check here so feeGrowthInside < feeGrowthInsideLast does not
  ///      look like near-uint256.max pending fees and brick an otherwise zero-fee position. Normal
  ///      valuation still uses `_feeOwed`'s modulo arithmetic to mirror V4 fee accounting.
  function _hasCollectableFeesForFailedCollect(address posm, uint256 tokenId) private view returns (bool) {
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

  function _validateVaultToken(address token) private view {
    require(ISharedVault(address(this)).isVaultToken(token), ISharedStrategy.InvalidPoolTokens());
  }

  function _requireWhitelistedPosm(address posm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), posm);
  }

  /// @dev Every positive-amount input must be both a vault token AND one of the pool currencies.
  ///      The currency match is essential: without it, an authorized executor could include a
  ///      non-pool vault token (e.g. DAI in a WETH/USDC mint) with a nonzero `gasFeeX64` and have
  ///      `_takeInputGasFeesAndGetPoolAmounts` siphon `amount * gasFeeX64 / Q64` of that token before
  ///      validation while the remainder dangles unused (never folded into `amount0`/`amount1`).
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
    address gasFeeRecipient;
    if (gasFeeX64 > 0) (gasFeeX64, gasFeeRecipient) = SharedStrategyFeeConfig.validateGasFeeX64(gasFeeX64);
    for (uint256 i; i < inputTokens.length;) {
      uint256 amount = inputTokens[i].amount;
      address token = Currency.unwrap(inputTokens[i].token);
      if (amount > 0 && gasFeeX64 > 0) {
        amount -= _applySingleTokenGasFee(token, amount, gasFeeX64, gasFeeRecipient);
      }
      if (inputTokens[i].token == currency0) amount0 += amount;
      else if (inputTokens[i].token == currency1) amount1 += amount;
      unchecked {
        i++;
      }
    }
  }

  function _applySingleTokenGasFee(
    address token,
    uint256 amount,
    uint64 gasFeeX64,
    address gasFeeRecipient
  ) private returns (uint256 gasFee) {
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
