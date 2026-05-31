// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { SharedNfpmProportionalExit } from "../libraries/SharedNfpmProportionalExit.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyFees } from "../libraries/SharedStrategyFees.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";

/// @title SharedV3Strategy
/// @notice Uniswap V3 LP operations for SharedVault with token validation and position tracking
contract SharedV3Strategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable swapRouter;

  uint256 private constant Q128 = 0x100000000000000000000000000000000;

  enum OperationType {
    SWAP_AND_MINT,
    SWAP_AND_INCREASE,
    /// @dev Historically named `SAFE_TRANSFER_NFT`; the NFT no longer moves — the strategy
    ///      executes the encoded instruction bytes inline. Renamed for clarity.
    EXECUTE_INSTRUCTIONS
  }

  constructor(address _swapRouter) {
    require(_swapRouter != address(0), ISharedCommon.ZeroAddress());
    swapRouter = _swapRouter;
  }

  /// @inheritdoc ISharedStrategy
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    OperationType opType = abi.decode(data[:32], (OperationType));

    if (opType == OperationType.SWAP_AND_MINT) {
      return _swapAndMint(data[32:]);
    } else if (opType == OperationType.SWAP_AND_INCREASE) {
      return _swapAndIncreaseLiquidity(data[32:]);
    } else if (opType == OperationType.EXECUTE_INSTRUCTIONS) {
      return _executeInstructions(data[32:]);
    } else {
      revert ISharedCommon.InvalidOperation();
    }
  }

  function _swapAndMint(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      IV3Utils.SwapAndMintParams memory params,
      address[] memory approveTokens,
      uint256[] memory approveAmounts,
      uint256 ethValue
    ) = abi.decode(data, (IV3Utils.SwapAndMintParams, address[], uint256[], uint256));

    _validateVaultToken(params.token0);
    _validateVaultToken(params.token1);

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, params.nfpm);

    _validateApprovalList(approveTokens, approveAmounts);

    uint256 tokenId;
    {
      (uint256 total0, uint256 total1) = _swapAndPrepareAmounts(params, ethValue);
      // F3: skim the configurable input gas fee to the authorized executor, mirroring the
      // V4/Pancake swap-and-mint path so the fee model is uniform across all four strategies.
      if (params.gasFeeX64 > 0) {
        (total0, total1) = _takeInputGasFee(params.token0, params.token1, total0, total1, params.gasFeeX64);
      }
      (tokenId, , , ) = _mintPosition(params, total0, total1);
    }

    // Return position change: new position added
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, params.nfpm, tokenId, params.token0, params.token1);
  }

  function _swapAndIncreaseLiquidity(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      IV3Utils.SwapAndIncreaseLiquidityParams memory params,
      address[] memory approveTokens,
      uint256[] memory approveAmounts,
      uint256 ethValue
    ) = abi.decode(data, (IV3Utils.SwapAndIncreaseLiquidityParams, address[], uint256[], uint256));

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, params.nfpm);
    require(IERC721(params.nfpm).ownerOf(params.tokenId) == address(this), InvalidPoolTokens());

    _validateApprovalList(approveTokens, approveAmounts);

    (, , address token0, address token1, , , , , , , , ) = INFPM(params.nfpm).positions(params.tokenId);
    (uint256 total0, uint256 total1) = _swapAndPrepareIncreaseAmounts(params, token0, token1, ethValue);
    // F3: skim the configurable input gas fee to the authorized executor (uniform with V4/Pancake).
    if (params.gasFeeX64 > 0) {
      (total0, total1) = _takeInputGasFee(token0, token1, total0, total1, params.gasFeeX64);
    }
    _increasePosition(
      params.nfpm,
      params.tokenId,
      token0,
      token1,
      total0,
      total1,
      params.amountAddMin0,
      params.amountAddMin1,
      params.deadline
    );

    // No position change — existing position updated, already tracked
    changes = new PositionChange[](0);
  }

  /// @dev Native V3Utils-style action execution. Generated LP fees are collected only for actions
  ///      that naturally consume fees. Platform and owner fees are taken from generated LP fees;
  ///      gas fee is taken from generated fees and, when liquidity is decreased, from principal too.
  ///      Despite the historical `SAFE_TRANSFER_NFT` name, the NFT itself is never transferred —
  ///      the strategy mutates the position in-place.
  function _executeInstructions(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, IV3Utils.Instructions memory instructions) = abi.decode(
      data,
      (address, uint256, IV3Utils.Instructions)
    );

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);

    (
      ,
      ,
      address token0,
      address token1,
      uint24 fee,
      int24 tickLower,
      int24 tickUpper,
      uint128 posLiquidity,
      ,
      ,
      ,

    ) = INFPM(nfpm).positions(tokenId);

    if (instructions.whatToDo == IV3Utils.WhatToDo.COMPOUND_FEES) {
      (uint256 fees0, uint256 fees1) = _collectGeneratedFees(
        nfpm,
        tokenId,
        token0,
        token1,
        instructions.gasFeeX64
      );
      (fees0, fees1) = _swapForCompound(token0, token1, fees0, fees1, instructions);
      _increasePosition(
        nfpm,
        tokenId,
        token0,
        token1,
        fees0,
        fees1,
        instructions.amountAddMin0,
        instructions.amountAddMin1,
        instructions.deadline
      );
      return new PositionChange[](0);
    }

    if (instructions.whatToDo == IV3Utils.WhatToDo.CHANGE_RANGE) {
      uint128 liquidityToRemove = instructions.liquidity == 0 || instructions.liquidity > posLiquidity
        ? posLiquidity
        : instructions.liquidity;
      (uint256 fees0, uint256 fees1) = _collectGeneratedFees(
        nfpm,
        tokenId,
        token0,
        token1,
        instructions.gasFeeX64
      );
      (uint256 principal0, uint256 principal1) = _decreasePrincipal(
        nfpm,
        tokenId,
        liquidityToRemove,
        instructions.amountRemoveMin0,
        instructions.amountRemoveMin1,
        token0,
        token1,
        instructions.gasFeeX64,
        instructions.deadline
      );

      uint256 total0 = principal0 + fees0;
      uint256 total1 = principal1 + fees1;
      (total0, total1) = _swapForCompound(token0, token1, total0, total1, instructions);

      IV3Utils.SwapAndMintParams memory mintParams = IV3Utils.SwapAndMintParams({
        protocol: instructions.protocol,
        nfpm: nfpm,
        token0: token0,
        token1: token1,
        fee: fee,
        tickSpacing: 0,
        tickLower: instructions.tickLower == 0 && instructions.tickUpper == 0 ? tickLower : instructions.tickLower,
        tickUpper: instructions.tickLower == 0 && instructions.tickUpper == 0 ? tickUpper : instructions.tickUpper,
        protocolFeeX64: 0,
        gasFeeX64: 0,
        amount0: total0,
        amount1: total1,
        amount2: 0,
        recipient: address(this),
        deadline: instructions.deadline,
        swapSourceToken: address(0),
        amountIn0: 0,
        amountOut0Min: 0,
        swapData0: "",
        amountIn1: 0,
        amountOut1Min: 0,
        swapData1: "",
        amountAddMin0: instructions.amountAddMin0,
        amountAddMin1: instructions.amountAddMin1,
        poolDeployer: address(0)
      });
      // L1: a genuinely empty source position (no liquidity) with nothing collected has nothing to
      // re-mint, and `INFPM.mint` reverts on `(0,0)` desired amounts. Untrack the empty position instead
      // of reverting the operator's tx. Gated on `posLiquidity == 0` so a normal rebalance (which always
      // yields >0 on at least one side) still mints and re-tracks exactly as before.
      if (posLiquidity == 0 && total0 == 0 && total1 == 0) {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
        return changes;
      }

      (uint256 newTokenId, , , ) = _mintPosition(mintParams, total0, total1);

      (, , , , , , , uint128 liqAfter, , , , ) = INFPM(nfpm).positions(tokenId);
      if (liqAfter == 0) {
        changes = new PositionChange[](2);
        changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
        changes[1] = PositionChange(true, nfpm, newTokenId, token0, token1);
      } else {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(true, nfpm, newTokenId, token0, token1);
      }
      return changes;
    }

    if (instructions.whatToDo == IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP) {
      (uint256 amount0, uint256 amount1) = _collectGeneratedFees(
        nfpm,
        tokenId,
        token0,
        token1,
        instructions.gasFeeX64
      );
      // Cap requested liquidity at the position's current liquidity to match V4's
      // `_decreaseV4Principal` semantics: oversized requests (e.g. `type(uint128).max` as a
      // full-exit sentinel) collapse to a full exit instead of reverting in the NFPM.
      // `liquidity == 0` still means "collect fees only, do not touch principal".
      uint128 liquidityToRemove = instructions.liquidity > posLiquidity ? posLiquidity : instructions.liquidity;
      (uint256 principal0, uint256 principal1) = _decreasePrincipal(
        nfpm,
        tokenId,
        liquidityToRemove,
        instructions.amountRemoveMin0,
        instructions.amountRemoveMin1,
        token0,
        token1,
        instructions.gasFeeX64,
        instructions.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      _swapForWithdraw(token0, token1, amount0, amount1, instructions);

      (, , , , , , , uint128 liqAfter, , , , ) = INFPM(nfpm).positions(tokenId);
      if (liqAfter == 0) {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
      } else {
        changes = new PositionChange[](0);
      }
      return changes;
    }

    revert ISharedCommon.InvalidOperation();
  }

  /// @inheritdoc ISharedStrategy
  function collectFees(address nfpm, uint256 tokenId, uint16 /* vaultOwnerFeeBasisPoint */) external override {
    _collectFees(nfpm, tokenId, SharedStrategyFeeConfig.performanceFeeConfig());
  }

  function _collectFees(address nfpm, uint256 tokenId, ICommon.FeeConfig memory perfFee) internal {
    (, , address token0, address token1, , , , , , , , ) = INFPM(nfpm).positions(tokenId);
    SharedNfpmProportionalExit.collectAccumulatedFees(nfpm, tokenId, token0, token1, perfFee);
  }

  function _decreaseVaultPosition(
    address nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 minAmount0,
    uint256 minAmount1,
    address token0,
    address token1
  ) internal {
    ICommon.FeeConfig memory perfFee = SharedStrategyFeeConfig.performanceFeeConfig();
    SharedNfpmProportionalExit.decreaseLiquidityProportional(
      nfpm,
      tokenId,
      liquidityToRemove,
      minAmount0,
      minAmount1,
      token0,
      token1,
      perfFee
    );
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Fee model: collect fees → take platform + vault-owner fees (direct transfer via
  ///      `SharedStrategyFees`) → decrease proportional liquidity → collect principal. No V3Utils fee fields.
  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 /* vaultOwnerFeeBasisPoint */
  ) external override returns (PositionChange[] memory changes) {
    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);

    (, , address token0, address token1, , , , uint128 posLiquidity, , , , ) = INFPM(nfpm).positions(tokenId);

    if (posLiquidity == 0) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) {
      return new PositionChange[](0);
    }

    bool isFullExit = liquidityToRemove >= posLiquidity;

    _decreaseVaultPosition(nfpm, tokenId, liquidityToRemove, minAmount0, minAmount1, token0, token1);

    if (isFullExit) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
  }

  function _swapAndPrepareAmounts(
    IV3Utils.SwapAndMintParams memory params,
    uint256 ethValue
  ) private returns (uint256 total0, uint256 total1) {
    require(ethValue == 0, ISharedCommon.InvalidAmount());

    if (params.swapSourceToken == params.token0) {
      require(params.amount0 >= params.amountIn1, ISharedCommon.InvalidAmount());
      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        params.token0,
        params.token1,
        params.amountIn1,
        params.amountOut1Min,
        params.swapData1
      );
      total0 = params.amount0 - amountInDelta;
      total1 = params.amount1 + amountOutDelta;
    } else if (params.swapSourceToken == params.token1) {
      require(params.amount1 >= params.amountIn0, ISharedCommon.InvalidAmount());
      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        params.token1,
        params.token0,
        params.amountIn0,
        params.amountOut0Min,
        params.swapData0
      );
      total1 = params.amount1 - amountInDelta;
      total0 = params.amount0 + amountOutDelta;
    } else if (params.swapSourceToken != address(0)) {
      _validateVaultToken(params.swapSourceToken);
      require(params.amountIn0 + params.amountIn1 <= params.amount2, ISharedCommon.InvalidAmount());
      (, uint256 amountOutDelta0) = _swap(
        params.swapSourceToken,
        params.token0,
        params.amountIn0,
        params.amountOut0Min,
        params.swapData0
      );
      (, uint256 amountOutDelta1) = _swap(
        params.swapSourceToken,
        params.token1,
        params.amountIn1,
        params.amountOut1Min,
        params.swapData1
      );
      total0 = params.amount0 + amountOutDelta0;
      total1 = params.amount1 + amountOutDelta1;
    } else {
      total0 = params.amount0;
      total1 = params.amount1;
    }
  }

  function _swapAndPrepareIncreaseAmounts(
    IV3Utils.SwapAndIncreaseLiquidityParams memory params,
    address token0,
    address token1,
    uint256 ethValue
  ) private returns (uint256 total0, uint256 total1) {
    require(ethValue == 0, ISharedCommon.InvalidAmount());

    if (params.swapSourceToken == token0) {
      require(params.amount0 >= params.amountIn1, ISharedCommon.InvalidAmount());
      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        token0,
        token1,
        params.amountIn1,
        params.amountOut1Min,
        params.swapData1
      );
      total0 = params.amount0 - amountInDelta;
      total1 = params.amount1 + amountOutDelta;
    } else if (params.swapSourceToken == token1) {
      require(params.amount1 >= params.amountIn0, ISharedCommon.InvalidAmount());
      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        token1,
        token0,
        params.amountIn0,
        params.amountOut0Min,
        params.swapData0
      );
      total1 = params.amount1 - amountInDelta;
      total0 = params.amount0 + amountOutDelta;
    } else if (params.swapSourceToken != address(0)) {
      _validateVaultToken(params.swapSourceToken);
      require(params.amountIn0 + params.amountIn1 <= params.amount2, ISharedCommon.InvalidAmount());
      (, uint256 amountOutDelta0) = _swap(
        params.swapSourceToken,
        token0,
        params.amountIn0,
        params.amountOut0Min,
        params.swapData0
      );
      (, uint256 amountOutDelta1) = _swap(
        params.swapSourceToken,
        token1,
        params.amountIn1,
        params.amountOut1Min,
        params.swapData1
      );
      total0 = params.amount0 + amountOutDelta0;
      total1 = params.amount1 + amountOutDelta1;
    } else {
      total0 = params.amount0;
      total1 = params.amount1;
    }
  }

  function _mintPosition(
    IV3Utils.SwapAndMintParams memory params,
    uint256 amount0Desired,
    uint256 amount1Desired
  ) private returns (uint256 tokenId, uint128 liquidity, uint256 added0, uint256 added1) {
    if (amount0Desired > 0) IERC20(params.token0).safeResetAndApprove(params.nfpm, amount0Desired);
    if (amount1Desired > 0) IERC20(params.token1).safeResetAndApprove(params.nfpm, amount1Desired);

    (tokenId, liquidity, added0, added1) = INFPM(params.nfpm).mint(
      INFPM.MintParams({
        token0: params.token0,
        token1: params.token1,
        fee: params.fee,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        amount0Desired: amount0Desired,
        amount1Desired: amount1Desired,
        amount0Min: params.amountAddMin0,
        amount1Min: params.amountAddMin1,
        recipient: address(this),
        deadline: params.deadline
      })
    );

    if (amount0Desired > 0) IERC20(params.token0).safeApprove(params.nfpm, 0);
    if (amount1Desired > 0) IERC20(params.token1).safeApprove(params.nfpm, 0);
  }

  function _increasePosition(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 deadline
  ) private {
    if (amount0Desired == 0 && amount1Desired == 0) return;

    if (amount0Desired > 0) IERC20(token0).safeResetAndApprove(nfpm, amount0Desired);
    if (amount1Desired > 0) IERC20(token1).safeResetAndApprove(nfpm, amount1Desired);

    INFPM(nfpm).increaseLiquidity(
      INFPM.IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: amount0Desired,
        amount1Desired: amount1Desired,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: deadline
      })
    );

    if (amount0Desired > 0) IERC20(token0).safeApprove(nfpm, 0);
    if (amount1Desired > 0) IERC20(token1).safeApprove(nfpm, 0);
  }

  function _collectGeneratedFees(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    uint64 gasFeeX64
  ) private returns (uint256 net0, uint256 net1) {
    (uint256 collected0, uint256 collected1) = INFPM(nfpm).collect(
      INFPM.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    if (collected0 == 0 && collected1 == 0) return (0, 0);

    ICommon.FeeConfig memory fc = SharedStrategyFeeConfig.performanceFeeConfig();
    if (gasFeeX64 > 0) {
      fc.gasFeeX64 = gasFeeX64;
      fc.gasFeeRecipient = msg.sender;
    }
    (uint256 fee0, uint256 fee1) = _takeFees(token0, collected0, token1, collected1, fc);
    net0 = collected0 - fee0;
    net1 = collected1 - fee1;
  }

  function _decreasePrincipal(
    address nfpm,
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    address token0,
    address token1,
    uint64 gasFeeX64,
    uint256 deadline
  ) private returns (uint256 net0, uint256 net1) {
    if (liquidity == 0) return (0, 0);

    INFPM(nfpm).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: deadline
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

    if (gasFeeX64 == 0 || (principal0 == 0 && principal1 == 0)) return (principal0, principal1);

    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: msg.sender
    });
    (uint256 fee0, uint256 fee1) = _takeFees(token0, principal0, token1, principal1, gasOnly);
    net0 = principal0 - fee0;
    net1 = principal1 - fee1;
  }

  /// @dev Direct proportional fee transfer (no `LpFeeTaker` swap/consolidation). Platform + vault owner +
  ///      gas slices of token0/token1 are sent straight to their recipients via `SharedStrategyFees`, which
  ///      clamps each fee to the running remainder so the total can never exceed the collected amount — this
  ///      makes the `collected - fee` accounting in the callers underflow-safe WITHOUT a separate
  ///      `<= 100%` revert guard, and matches the V4/Pancake fee model exactly (uniform across all four).
  function _takeFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    ICommon.FeeConfig memory fc
  ) private returns (uint256 fee0, uint256 fee1) {
    if (
      (amount0 == 0 && amount1 == 0) ||
      (fc.platformFeeBasisPoint == 0 && fc.vaultOwnerFeeBasisPoint == 0 && fc.gasFeeX64 == 0)
    ) return (0, 0);

    (fee0, fee1) = SharedStrategyFees.applyFees(token0, amount0, token1, amount1, fc);
  }

  /// @dev F3: skim a configurable gas fee from the prepared (post-swap) pool amounts to the authorized
  ///      executor, mirroring SharedV4StrategyLib's swap-and-mint/increase input gas-fee behavior so the
  ///      fee model is uniform across V3/Aerodrome/V4/Pancake. Settled via `SharedStrategyFees` so it is
  ///      observable via FeeCollected. Both amounts are pool currencies here, so nothing untracked leaves
  ///      the vault.
  function _takeInputGasFee(
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    uint64 gasFeeX64
  ) private returns (uint256 net0, uint256 net1) {
    if (gasFeeX64 == 0 || (amount0 == 0 && amount1 == 0)) return (amount0, amount1);
    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: msg.sender
    });
    (uint256 fee0, uint256 fee1) = _takeFees(token0, amount0, token1, amount1, gasOnly);
    net0 = amount0 - fee0;
    net1 = amount1 - fee1;
  }

  function _swapForCompound(
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    IV3Utils.Instructions memory instructions
  ) private returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;
    if (instructions.targetToken == token0) {
      require(total1 >= instructions.amountIn1, ISharedCommon.InvalidAmount());
      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        token1,
        token0,
        instructions.amountIn1,
        instructions.amountOut1Min,
        instructions.swapData1
      );
      total1 -= amountInDelta;
      total0 += amountOutDelta;
    } else if (instructions.targetToken == token1) {
      require(total0 >= instructions.amountIn0, ISharedCommon.InvalidAmount());
      (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
        token0,
        token1,
        instructions.amountIn0,
        instructions.amountOut0Min,
        instructions.swapData0
      );
      total0 -= amountInDelta;
      total1 += amountOutDelta;
    }
  }

  function _swapForWithdraw(
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    IV3Utils.Instructions memory instructions
  ) private {
    if (instructions.targetToken == address(0)) return;
    _validateVaultToken(instructions.targetToken);
    if (token0 != instructions.targetToken) {
      _swap(token0, instructions.targetToken, amount0, instructions.amountOut0Min, instructions.swapData0);
    }
    if (token1 != instructions.targetToken) {
      _swap(token1, instructions.targetToken, amount1, instructions.amountOut1Min, instructions.swapData1);
    }
  }

  function _swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory swapData
  ) private returns (uint256 amountInDelta, uint256 amountOutDelta) {
    if (amountIn == 0 || swapData.length == 0 || tokenOut == address(0)) return (0, 0);
    _validateVaultToken(tokenIn);
    _validateVaultToken(tokenOut);
    // Defense-in-depth kill-switch: re-validate the immutable swapRouter against the live ConfigManager
    // whitelist at execution time (parity with SharedV4StrategyLib._executeV4Swaps), so the owner can
    // revoke a compromised/deprecated aggregator without redeploying the strategy.
    require(
      ISharedVault(address(this)).configManager().isWhitelistedSwapRouter(swapRouter),
      ISharedCommon.InvalidSwapRouter(swapRouter)
    );

    uint256 balanceInBefore = IERC20(tokenIn).balanceOf(address(this));
    uint256 balanceOutBefore = IERC20(tokenOut).balanceOf(address(this));

    IERC20(tokenIn).safeResetAndApprove(swapRouter, amountIn);
    (bool success, ) = swapRouter.call(swapData);
    if (!success) revert ISharedCommon.SwapFailed();
    IERC20(tokenIn).safeApprove(swapRouter, 0);

    uint256 balanceInAfter = IERC20(tokenIn).balanceOf(address(this));
    uint256 balanceOutAfter = IERC20(tokenOut).balanceOf(address(this));

    amountInDelta = balanceInBefore - balanceInAfter;
    amountOutDelta = balanceOutAfter - balanceOutBefore;
    require(amountOutDelta >= amountOutMin, ISharedCommon.InsufficientOutput());
  }

  /// @inheritdoc ISharedStrategy
  /// @dev `slippageBps` lowers amount mins from desired (e.g. 100 = 1% tolerance). When 0, mins are
  ///      0 so the pool may consume the usual partial split (see `ISharedStrategy.depositProportional`).
  ///      Out-of-range positions have one desired amount zero, so that side's min stays 0.
  function depositProportional(
    address nfpm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16 slippageBps
  ) external override {
    if (amount0 == 0 && amount1 == 0) return;

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);

    (, , address token0, address token1, , , , , , , , ) = INFPM(nfpm).positions(tokenId);
    if (amount0 > 0) IERC20(token0).safeResetAndApprove(nfpm, amount0);
    if (amount1 > 0) IERC20(token1).safeResetAndApprove(nfpm, amount1);
    uint256 amount0Min;
    uint256 amount1Min;
    if (slippageBps > 0) {
      uint256 scale = 10000 - slippageBps;
      amount0Min = FullMath.mulDiv(amount0, scale, 10000);
      amount1Min = FullMath.mulDiv(amount1, scale, 10000);
    }
    INFPM(nfpm).increaseLiquidity(
      INFPM.IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: block.timestamp
      })
    );
    if (amount0 > 0) IERC20(token0).safeApprove(nfpm, 0);
    if (amount1 > 0) IERC20(token1).safeApprove(nfpm, 0);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionAmounts(
    address nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    // Not gated by `configManager` here: the vault calls this via **external** `staticcall` / `call`
    // (`address(this)` is the strategy), so `ISharedVault(address(this)).configManager()` would read
    // the wrong contract. NFPM trust is enforced on `delegatecall` paths and on `_addPosition` in the vault.
    // Aerodrome / Pancake shared strategies use the same rule on this function (no whitelist on valuation).

    (uint256 principal0, uint256 principal1, uint256 tokensOwed0, uint256 tokensOwed1) = _positionAmountsSplit(
      nfpm,
      tokenId
    );
    amount0 = principal0 + tokensOwed0;
    amount1 = principal1 + tokensOwed1;
  }

  /// @inheritdoc ISharedStrategy
  function getPositionTokens(
    address nfpm,
    uint256 tokenId
  ) external view override returns (address token0, address token1) {
    (, , token0, token1, , , , , , , , ) = INFPM(nfpm).positions(tokenId);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionPrincipalAmounts(
    address nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    // Principal-only: excludes tokensOwed so SharedVault tops up existing positions at the exact
    // range ratio increaseLiquidity requires. See ISharedStrategy.getPositionPrincipalAmounts.
    (amount0, amount1, , ) = _positionAmountsSplit(nfpm, tokenId);
  }

  /// @dev Splits a position's on-chain amounts into principal (from in-range liquidity at current price)
  ///      and uncollected fees (`tokensOwed*`). Returns (0, 0, 0, 0) for fully-zeroed positions to match
  ///      the short-circuit in `getPositionAmounts` and avoid an unnecessary pool `slot0` staticcall.
  ///      Uses try/catch for positions() so that burned or nonexistent NFTs (which cause positions() to
  ///      revert on standard V3 NFPMs) return (0,0,0,0) rather than propagating the revert up through
  ///      getPositionAmounts. Without this, _verifyPositionExit's staticcall to getPositionAmounts would
  ///      receive amtsOk=false and block the untracking even for a legitimately exited position on a
  ///      non-standard NFPM that keeps ownerOf() working after the position is burned.
  function _positionAmountsSplit(
    address nfpm,
    uint256 tokenId
  ) private view returns (uint256 principal0, uint256 principal1, uint256 tokensOwed0, uint256 tokensOwed1) {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 owed0;
    uint128 owed1;
    try INFPM(nfpm).positions(tokenId) returns (
      uint96,
      address,
      address _token0,
      address _token1,
      uint24 _fee,
      int24 _tickLower,
      int24 _tickUpper,
      uint128 _liquidity,
      uint256 _fg0Last,
      uint256 _fg1Last,
      uint128 _owed0,
      uint128 _owed1
    ) {
      token0 = _token0;
      token1 = _token1;
      fee = _fee;
      tickLower = _tickLower;
      tickUpper = _tickUpper;
      liquidity = _liquidity;
      feeGrowthInside0LastX128 = _fg0Last;
      feeGrowthInside1LastX128 = _fg1Last;
      owed0 = _owed0;
      owed1 = _owed1;
    } catch {
      return (0, 0, 0, 0);
    }

    tokensOwed0 = owed0;
    tokensOwed1 = owed1;

    if (liquidity == 0) return (0, 0, tokensOwed0, tokensOwed1);

    address pool = _getPool(nfpm, token0, token1, fee);
    (bool success, bytes memory returnedData) = pool.staticcall(abi.encodeWithSignature("slot0()"));
    require(success, ISharedCommon.StrategyCallFailed());
    uint160 sqrtPriceX96;
    int24 tick;
    assembly {
      sqrtPriceX96 := mload(add(returnedData, 0x20))
      tick := mload(add(returnedData, 0x40))
    }
    (principal0, principal1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      liquidity
    );

    // Include fees accrued since the last position update / collect (fee-growth delta).
    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = _getFeeGrowthInside(
      IUniswapV3Pool(pool),
      tickLower,
      tickUpper,
      tick
    );
    // F7: the fee-growth subtraction wraps by design (matches Uniswap V3), but the pending-fee
    // accumulation is done in uint256 and is NOT truncated to uint128. The previous
    // `uint128(mulDiv(...))` inside `unchecked` could silently wrap (under-reporting fees in this
    // valuation) at extreme fee growth; valuing in uint256 avoids both that silent wrap and the
    // reverting SafeCast the V4/Pancake libs use, so getPositionAmounts always values reliably.
    uint256 delta0;
    uint256 delta1;
    unchecked {
      delta0 = feeGrowthInside0X128 - feeGrowthInside0LastX128;
      delta1 = feeGrowthInside1X128 - feeGrowthInside1LastX128;
    }
    tokensOwed0 = uint256(owed0) + FullMath.mulDiv(delta0, liquidity, Q128);
    tokensOwed1 = uint256(owed1) + FullMath.mulDiv(delta1, liquidity, Q128);
  }

  /// @dev Computes fee growth inside [tickLower, tickUpper] using the standard Uniswap V3 formula:
  ///      feeGrowthInside = feeGrowthGlobal − feeGrowthBelow − feeGrowthAbove.
  ///      If a tick is uninitialized (feeGrowthOutside == 0), the math remains correct:
  ///      — In-range (tick between lower and upper) with both outsides = 0: result = global (all fees inside).
  ///      — Below range (tick < lower) with lower outside = 0: fgBelow = global − 0 = global → result = 0.
  ///      — Above range (tick ≥ upper) with upper outside = 0: fgAbove = global → result = 0.
  ///      A live tracked position always has its ticks initialized (liquidity was added), but this
  ///      property ensures the helper is safe even in hypothetical edge-case invocations.
  function _getFeeGrowthInside(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) private view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    unchecked {
      (, , uint256 lowerFg0Outside, uint256 lowerFg1Outside, , , , ) = pool.ticks(tickLower);
      (, , uint256 upperFg0Outside, uint256 upperFg1Outside, , , , ) = pool.ticks(tickUpper);
      uint256 fg0Global = pool.feeGrowthGlobal0X128();
      uint256 fg1Global = pool.feeGrowthGlobal1X128();

      uint256 fg0Below = tickCurrent >= tickLower ? lowerFg0Outside : fg0Global - lowerFg0Outside;
      uint256 fg1Below = tickCurrent >= tickLower ? lowerFg1Outside : fg1Global - lowerFg1Outside;
      uint256 fg0Above = tickCurrent < tickUpper ? upperFg0Outside : fg0Global - upperFg0Outside;
      uint256 fg1Above = tickCurrent < tickUpper ? upperFg1Outside : fg1Global - upperFg1Outside;

      feeGrowthInside0X128 = fg0Global - fg0Below - fg0Above;
      feeGrowthInside1X128 = fg1Global - fg1Below - fg1Above;
    }
  }

  function _getPool(address nfpm, address token0, address token1, uint24 fee) internal view returns (address) {
    address factory = INFPM(nfpm).factory();
    return IUniswapV3Factory(factory).getPool(token0, token1, fee);
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  /// @dev `approveTokens` / `approveAmounts` are NOT used to issue ERC20 approvals — those happen
  ///      per-hop inside `_swap` against the immutable `swapRouter`. They are walked here purely
  ///      to enforce that any positive-amount entry references a vault-tracked token, blocking
  ///      operators from sneaking unrelated tokens through this entry point.
  function _validateApprovalList(address[] memory _tokens, uint256[] memory approveAmounts) internal view {
    require(_tokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < _tokens.length; ) {
      if (approveAmounts[i] > 0) {
        _validateVaultToken(_tokens[i]);
      }
      unchecked {
        i++;
      }
    }
  }
}
