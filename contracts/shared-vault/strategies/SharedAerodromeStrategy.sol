// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { INonfungiblePositionManager } from "../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import { ICLFactory } from "../../common/interfaces/protocols/aerodrome/ICLFactory.sol";
import { ICLPool } from "../../common/interfaces/protocols/aerodrome/ICLPool.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { ILpFeeTaker } from "../../public-vault/interfaces/strategies/ILpFeeTaker.sol";
import { SharedNfpmProportionalExit } from "../libraries/SharedNfpmProportionalExit.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";

/// @title SharedAerodromeStrategy
/// @notice Aerodrome CL LP operations for SharedVault with token validation and position tracking.
///         Uses Aerodrome's tickSpacing-based pool lookup (ICLFactory.getPool(address,address,int24))
///         instead of Uniswap V3's fee-based lookup — the only structural difference from SharedV3Strategy.
contract SharedAerodromeStrategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable swapRouter;
  address public immutable lpFeeTaker;

  uint256 private constant Q128 = 0x100000000000000000000000000000000;

  enum OperationType {
    SWAP_AND_MINT,
    SWAP_AND_INCREASE,
    /// @dev Historically named `SAFE_TRANSFER_NFT`; the NFT no longer moves — the strategy
    ///      executes the encoded instruction bytes inline. Renamed for clarity.
    EXECUTE_INSTRUCTIONS
  }

  constructor(address _swapRouter, address _lpFeeTaker) {
    require(_swapRouter != address(0) && _lpFeeTaker != address(0), ISharedCommon.ZeroAddress());
    swapRouter = _swapRouter;
    lpFeeTaker = _lpFeeTaker;
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
    _requireAerodromeNfpm(params.nfpm);

    _validateApprovalList(approveTokens, approveAmounts);

    uint256 tokenId;
    {
      (uint256 total0, uint256 total1) = _swapAndPrepareAmounts(params, ethValue);
      (tokenId, , , ) = _mintPosition(params, total0, total1);
    }

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

    _requireAerodromeNfpm(params.nfpm);
    require(IERC721(params.nfpm).ownerOf(params.tokenId) == address(this), InvalidPoolTokens());

    _validateApprovalList(approveTokens, approveAmounts);

    (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(params.nfpm).positions(
      params.tokenId
    );
    (uint256 total0, uint256 total1) = _swapAndPrepareIncreaseAmounts(params, token0, token1, ethValue);
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

    changes = new PositionChange[](0);
  }

  /// @dev Despite the historical `SAFE_TRANSFER_NFT` name, the NFT itself is never transferred —
  ///      the strategy mutates the position in-place.
  function _executeInstructions(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address _nfpm, uint256 tokenId, IV3Utils.Instructions memory instructions) = abi.decode(
      data,
      (address, uint256, IV3Utils.Instructions)
    );

    _requireAerodromeNfpm(_nfpm);

    (
      ,
      ,
      address token0,
      address token1,
      int24 tickSpacing,
      int24 tickLower,
      int24 tickUpper,
      uint128 posLiquidity,
      ,
      ,
      ,

    ) = INonfungiblePositionManager(_nfpm).positions(tokenId);

    address pool = _getPool(_nfpm, token0, token1, tickSpacing);

    if (instructions.whatToDo == IV3Utils.WhatToDo.COMPOUND_FEES) {
      (uint256 fees0, uint256 fees1) = _collectGeneratedFees(
        _nfpm,
        tokenId,
        token0,
        token1,
        pool,
        instructions.gasFeeX64
      );
      (fees0, fees1) = _swapForCompound(token0, token1, fees0, fees1, instructions);
      _increasePosition(
        _nfpm,
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
        _nfpm,
        tokenId,
        token0,
        token1,
        pool,
        instructions.gasFeeX64
      );
      (uint256 principal0, uint256 principal1) = _decreasePrincipal(
        _nfpm,
        tokenId,
        liquidityToRemove,
        instructions.amountRemoveMin0,
        instructions.amountRemoveMin1,
        token0,
        token1,
        pool,
        instructions.gasFeeX64,
        instructions.deadline
      );
      uint256 total0 = fees0 + principal0;
      uint256 total1 = fees1 + principal1;
      (total0, total1) = _swapForCompound(token0, token1, total0, total1, instructions);

      IV3Utils.SwapAndMintParams memory mintParams = IV3Utils.SwapAndMintParams({
        protocol: instructions.protocol,
        nfpm: _nfpm,
        token0: token0,
        token1: token1,
        fee: 0,
        tickSpacing: tickSpacing,
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
      (uint256 newTokenId, , , ) = _mintPosition(mintParams, total0, total1);

      (, , , , , , , uint128 liqAfter, , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
      if (liqAfter == 0) {
        changes = new PositionChange[](2);
        changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
        changes[1] = PositionChange(true, _nfpm, newTokenId, token0, token1);
      } else {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(true, _nfpm, newTokenId, token0, token1);
      }
      return changes;
    }

    if (instructions.whatToDo == IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP) {
      (uint256 amount0, uint256 amount1) = _collectGeneratedFees(
        _nfpm,
        tokenId,
        token0,
        token1,
        pool,
        instructions.gasFeeX64
      );
      // Cap requested liquidity at the position's current liquidity to match V4's
      // `_decreaseV4Principal` semantics: oversized requests (e.g. `type(uint128).max` as a
      // full-exit sentinel) collapse to a full exit instead of reverting in the NFPM.
      // `liquidity == 0` still means "collect fees only, do not touch principal".
      uint128 liquidityToRemove = instructions.liquidity > posLiquidity ? posLiquidity : instructions.liquidity;
      (uint256 principal0, uint256 principal1) = _decreasePrincipal(
        _nfpm,
        tokenId,
        liquidityToRemove,
        instructions.amountRemoveMin0,
        instructions.amountRemoveMin1,
        token0,
        token1,
        pool,
        instructions.gasFeeX64,
        instructions.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      _swapForWithdraw(token0, token1, amount0, amount1, instructions);

      (, , , , , , , uint128 liqAfter, , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
      if (liqAfter == 0) {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      } else {
        changes = new PositionChange[](0);
      }
      return changes;
    }

    revert ISharedCommon.InvalidOperation();
  }

  /// @inheritdoc ISharedStrategy
  function collectFees(address _nfpm, uint256 tokenId, uint16 /* vaultOwnerFeeBasisPoint */) external override {
    _collectFees(_nfpm, tokenId, SharedStrategyFeeConfig.performanceFeeConfig());
  }

  function _collectFees(address _nfpm, uint256 tokenId, ICommon.FeeConfig memory perfFee) internal {
    (, , address token0, address token1, int24 tickSpacing, , , , , , , ) = INonfungiblePositionManager(_nfpm)
      .positions(tokenId);
    address pool = _getPool(_nfpm, token0, token1, tickSpacing);
    SharedNfpmProportionalExit.collectAccumulatedFees(_nfpm, tokenId, token0, token1, pool, lpFeeTaker, perfFee);
  }

  function _decreaseVaultPosition(
    address _nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 minAmount0,
    uint256 minAmount1,
    address token0,
    address token1,
    int24 tickSpacing
  ) internal {
    address pool = _getPool(_nfpm, token0, token1, tickSpacing);
    ICommon.FeeConfig memory perfFee = SharedStrategyFeeConfig.performanceFeeConfig();
    SharedNfpmProportionalExit.decreaseLiquidityProportional(
      _nfpm,
      tokenId,
      liquidityToRemove,
      minAmount0,
      minAmount1,
      token0,
      token1,
      pool,
      lpFeeTaker,
      perfFee
    );
  }

  /// @inheritdoc ISharedStrategy
  function exitProportional(
    address _nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 /* vaultOwnerFeeBasisPoint */
  ) external override returns (PositionChange[] memory changes) {
    _requireAerodromeNfpm(_nfpm);

    (
      ,
      ,
      address token0,
      address token1,
      int24 tickSpacing,
      ,
      ,
      uint128 posLiquidity,
      ,
      ,
      ,

    ) = INonfungiblePositionManager(_nfpm).positions(tokenId);

    if (posLiquidity == 0) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) {
      return new PositionChange[](0);
    }

    bool isFullExit = liquidityToRemove >= posLiquidity;

    _decreaseVaultPosition(_nfpm, tokenId, liquidityToRemove, minAmount0, minAmount1, token0, token1, tickSpacing);

    if (isFullExit) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
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

    (tokenId, liquidity, added0, added1) = INonfungiblePositionManager(params.nfpm).mint(
      INonfungiblePositionManager.MintParams({
        token0: params.token0,
        token1: params.token1,
        tickSpacing: params.tickSpacing,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        amount0Desired: amount0Desired,
        amount1Desired: amount1Desired,
        amount0Min: params.amountAddMin0,
        amount1Min: params.amountAddMin1,
        recipient: address(this),
        deadline: params.deadline,
        sqrtPriceX96: 0
      })
    );

    if (amount0Desired > 0) IERC20(params.token0).safeApprove(params.nfpm, 0);
    if (amount1Desired > 0) IERC20(params.token1).safeApprove(params.nfpm, 0);
  }

  function _increasePosition(
    address _nfpm,
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

    if (amount0Desired > 0) IERC20(token0).safeResetAndApprove(_nfpm, amount0Desired);
    if (amount1Desired > 0) IERC20(token1).safeResetAndApprove(_nfpm, amount1Desired);

    INonfungiblePositionManager(_nfpm).increaseLiquidity(
      INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: amount0Desired,
        amount1Desired: amount1Desired,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: deadline
      })
    );

    if (amount0Desired > 0) IERC20(token0).safeApprove(_nfpm, 0);
    if (amount1Desired > 0) IERC20(token1).safeApprove(_nfpm, 0);
  }

  function _collectGeneratedFees(
    address _nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    address pool,
    uint64 gasFeeX64
  ) private returns (uint256 net0, uint256 net1) {
    (uint256 collected0, uint256 collected1) = INonfungiblePositionManager(_nfpm).collect(
      INonfungiblePositionManager.CollectParams({
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
    (uint256 fee0, uint256 fee1) = _takeFees(token0, collected0, token1, collected1, pool, fc);
    net0 = collected0 - fee0;
    net1 = collected1 - fee1;
  }

  function _decreasePrincipal(
    address _nfpm,
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    address token0,
    address token1,
    address pool,
    uint64 gasFeeX64,
    uint256 deadline
  ) private returns (uint256 net0, uint256 net1) {
    if (liquidity == 0) return (0, 0);

    INonfungiblePositionManager(_nfpm).decreaseLiquidity(
      INonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: deadline
      })
    );

    (uint256 principal0, uint256 principal1) = INonfungiblePositionManager(_nfpm).collect(
      INonfungiblePositionManager.CollectParams({
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
    (uint256 fee0, uint256 fee1) = _takeFees(token0, principal0, token1, principal1, pool, gasOnly);
    net0 = principal0 - fee0;
    net1 = principal1 - fee1;
  }

  function _takeFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    address pool,
    ICommon.FeeConfig memory fc
  ) private returns (uint256 fee0, uint256 fee1) {
    if (
      (amount0 == 0 && amount1 == 0) ||
      (fc.platformFeeBasisPoint == 0 && fc.vaultOwnerFeeBasisPoint == 0 && fc.gasFeeX64 == 0)
    ) return (0, 0);

    if (amount0 > 0) IERC20(token0).safeResetAndApprove(lpFeeTaker, amount0);
    if (amount1 > 0) IERC20(token1).safeResetAndApprove(lpFeeTaker, amount1);
    (fee0, fee1) = ILpFeeTaker(lpFeeTaker).takeFees(token0, amount0, token1, amount1, fc, token0, pool, address(0));
    if (amount0 > 0) IERC20(token0).safeApprove(lpFeeTaker, 0);
    if (amount1 > 0) IERC20(token1).safeApprove(lpFeeTaker, 0);
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
  /// @dev Not gated by configManager whitelist — called via external CALL from the vault (not delegatecall),
  ///      so `address(this)` is the strategy; NFPM trust is enforced on all mutating delegatecall paths.
  function getPositionAmounts(
    address _nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    (uint256 principal0, uint256 principal1, uint128 tokensOwed0, uint128 tokensOwed1) = _positionAmountsSplit(
      _nfpm,
      tokenId
    );
    amount0 = principal0 + tokensOwed0;
    amount1 = principal1 + tokensOwed1;
  }

  /// @inheritdoc ISharedStrategy
  function getPositionTokens(
    address _nfpm,
    uint256 tokenId
  ) external view override returns (address token0, address token1) {
    (, , token0, token1, , , , , , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionPrincipalAmounts(
    address _nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    (amount0, amount1, , ) = _positionAmountsSplit(_nfpm, tokenId);
  }

  /// @dev See note on `SharedV3Strategy._positionAmountsSplit`. Identical semantics, adapted for the
  ///      Aerodrome tickSpacing-based pool lookup. Uses try/catch for positions() for the same reason:
  ///      burned or nonexistent NFTs must return (0,0,0,0) rather than reverting getPositionAmounts,
  ///      which would cause _verifyPositionExit to block legitimate untracking operations.
  function _positionAmountsSplit(
    address _nfpm,
    uint256 tokenId
  ) private view returns (uint256 principal0, uint256 principal1, uint128 tokensOwed0, uint128 tokensOwed1) {
    address token0;
    address token1;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 owed0;
    uint128 owed1;
    try INonfungiblePositionManager(_nfpm).positions(tokenId) returns (
      uint96,
      address,
      address _token0,
      address _token1,
      int24 _tickSpacing,
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
      tickSpacing = _tickSpacing;
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

    address pool = _getPool(_nfpm, token0, token1, tickSpacing);
    (uint160 sqrtPriceX96, int24 tick, , , , ) = ICLPool(pool).slot0();
    (principal0, principal1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      liquidity
    );

    // Include fees accrued since the last position update / collect (fee-growth delta).
    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = _getFeeGrowthInside(
      ICLPool(pool),
      tickLower,
      tickUpper,
      tick
    );
    unchecked {
      tokensOwed0 += uint128(FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, Q128));
      tokensOwed1 += uint128(FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, Q128));
    }
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
    ICLPool pool,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) private view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    unchecked {
      (, , , uint256 lowerFg0Outside, uint256 lowerFg1Outside, , , , , ) = pool.ticks(tickLower);
      (, , , uint256 upperFg0Outside, uint256 upperFg1Outside, , , , , ) = pool.ticks(tickUpper);
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

  /// @inheritdoc ISharedStrategy
  function depositProportional(
    address _nfpm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16 slippageBps
  ) external override {
    if (amount0 == 0 && amount1 == 0) return;

    _requireAerodromeNfpm(_nfpm);

    (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
    if (amount0 > 0) IERC20(token0).safeResetAndApprove(_nfpm, amount0);
    if (amount1 > 0) IERC20(token1).safeResetAndApprove(_nfpm, amount1);
    uint256 amount0Min;
    uint256 amount1Min;
    if (slippageBps > 0) {
      uint256 scale = 10000 - slippageBps;
      amount0Min = FullMath.mulDiv(amount0, scale, 10000);
      amount1Min = FullMath.mulDiv(amount1, scale, 10000);
    }
    INonfungiblePositionManager(_nfpm).increaseLiquidity(
      INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        deadline: block.timestamp
      })
    );
    if (amount0 > 0) IERC20(token0).safeApprove(_nfpm, 0);
    if (amount1 > 0) IERC20(token1).safeApprove(_nfpm, 0);
  }

  function _getPool(address _nfpm, address token0, address token1, int24 tickSpacing) internal view returns (address) {
    address factory = INonfungiblePositionManager(_nfpm).factory();
    return ICLFactory(factory).getPool(token0, token1, tickSpacing);
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

  function _requireAerodromeNfpm(address _nfpm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), _nfpm);
  }
}
