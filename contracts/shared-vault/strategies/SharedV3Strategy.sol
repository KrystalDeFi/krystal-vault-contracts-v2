// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
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

/// @dev Generic NFPM for querying positions
interface INFPM {
  function positions(
    uint256 tokenId
  )
    external
    view
    returns (
      uint96,
      address,
      address token0,
      address token1,
      int24 feeOrTickSpacing,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint256,
      uint256,
      uint128,
      uint128
    );

  function factory() external view returns (address);
}

/// @dev UniswapV3 factory for pool lookup (fee as uint24)
interface IUniV3Factory {
  function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

/// @dev UniswapV3 pool for slot0 query
interface IUniV3Pool {
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint8 feeProtocol,
      bool unlocked
    );
}

/// @title SharedV3Strategy
/// @notice Uniswap V3 LP operations for SharedVault with token validation and position tracking
contract SharedV3Strategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable v3utils;
  address public immutable lpFeeTaker;

  enum OperationType {
    SWAP_AND_MINT,
    SWAP_AND_INCREASE,
    SAFE_TRANSFER_NFT
  }

  constructor(address _v3utils, address _lpFeeTaker) {
    require(_v3utils != address(0) && _lpFeeTaker != address(0), ISharedCommon.ZeroAddress());
    v3utils = _v3utils;
    lpFeeTaker = _lpFeeTaker;
  }

  /// @inheritdoc ISharedStrategy
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    OperationType opType = abi.decode(data[:32], (OperationType));

    if (opType == OperationType.SWAP_AND_MINT) {
      return _swapAndMint(data[32:]);
    } else if (opType == OperationType.SWAP_AND_INCREASE) {
      return _swapAndIncreaseLiquidity(data[32:]);
    } else if (opType == OperationType.SAFE_TRANSFER_NFT) {
      return _safeTransferNft(data[32:]);
    } else {
      revert ISharedCommon.InvalidOperation();
    }
  }

  function _swapAndMint(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      IV3Utils.SwapAndMintParams memory params,
      address[] memory approveTokens,
      uint256[] memory approveAmounts,
      uint256 ethValue,
      uint16 platformFeeBasisPointOverride,
      uint64 gasFeeX64Override
    ) = abi.decode(data, (IV3Utils.SwapAndMintParams, address[], uint256[], uint256, uint16, uint64));

    _validateVaultToken(params.token0);
    _validateVaultToken(params.token1);

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    params.protocolFeeX64 = SharedStrategyFeeConfig.platformFeeX64(cm, platformFeeBasisPointOverride);
    params.gasFeeX64 = gasFeeX64Override;

    IV3Utils.SwapAndMintResult memory result = IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);

    // Return position change: new position added
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, params.nfpm, result.tokenId, params.token0, params.token1);
  }

  function _swapAndIncreaseLiquidity(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      IV3Utils.SwapAndIncreaseLiquidityParams memory params,
      address[] memory approveTokens,
      uint256[] memory approveAmounts,
      uint256 ethValue,
      uint16 platformFeeBasisPointOverride,
      uint64 gasFeeX64Override
    ) = abi.decode(data, (IV3Utils.SwapAndIncreaseLiquidityParams, address[], uint256[], uint256, uint16, uint64));

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    params.protocolFeeX64 = SharedStrategyFeeConfig.platformFeeX64(cm, platformFeeBasisPointOverride);
    params.gasFeeX64 = gasFeeX64Override;

    IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);

    // No position change — existing position updated, already tracked
    changes = new PositionChange[](0);
  }

  /// @dev For CHANGE_RANGE: caller must provide newTokenId (the NFT minted by V3Utils for the new position).
  ///      The caller can predict this via NFPM._nextId() or tx simulation.
  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      address nfpm,
      uint256 tokenId,
      IV3Utils.Instructions memory instructions,
      bool isFullWithdraw,
      uint256 newTokenId,
      uint16 platformFeeBasisPointOverride,
      uint64 gasFeeX64Override
    ) = abi.decode(data, (address, uint256, IV3Utils.Instructions, bool, uint256, uint16, uint64));

    instructions.recipient = address(this);
    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    instructions.performanceFeeX64 = SharedStrategyFeeConfig.platformFeeX64(cm, platformFeeBasisPointOverride);
    instructions.gasFeeX64 = gasFeeX64Override;
    IERC721(nfpm).safeTransferFrom(address(this), v3utils, tokenId, abi.encode(instructions));

    if (instructions.whatToDo == IV3Utils.WhatToDo.CHANGE_RANGE) {
      // Atomic: remove old + add new in same call
      (, , address token0, address token1, , , , , , , , ) = INFPM(nfpm).positions(tokenId);
      require(newTokenId != 0, InvalidPoolTokens());
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
      changes[1] = PositionChange(true, nfpm, newTokenId, token0, token1);
    } else if (isFullWithdraw) {
      (, , address token0, address token1, , , , , , , , ) = INFPM(nfpm).positions(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
  }

  function _decreaseVaultPosition(
    address nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 minAmount0,
    uint256 minAmount1,
    address token0,
    address token1,
    int24 feeOrTickSpacing,
    uint16 vaultOwnerFeeBasisPoint
  ) internal {
    address pool = _getPool(nfpm, token0, token1, uint24(feeOrTickSpacing));
    ICommon.FeeConfig memory perfFee = SharedStrategyFeeConfig.performanceFeeConfig(vaultOwnerFeeBasisPoint);
    SharedNfpmProportionalExit.decreaseLiquidityProportional(
      nfpm,
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
  /// @dev Same fee model as public `LpStrategy._decreaseLiquidity`: collect fees → `LpFeeTaker.takeFees`
  ///      (platform + vault owner) → decrease proportional liquidity → collect principal. No V3Utils fee fields.
  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 vaultOwnerFeeBasisPoint
  ) external override returns (PositionChange[] memory changes) {
    (, , address token0, address token1, int24 feeOrTickSpacing, , , uint128 posLiquidity, , , , ) = INFPM(nfpm)
      .positions(tokenId);

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

    _decreaseVaultPosition(
      nfpm,
      tokenId,
      liquidityToRemove,
      minAmount0,
      minAmount1,
      token0,
      token1,
      feeOrTickSpacing,
      vaultOwnerFeeBasisPoint
    );

    if (isFullExit) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
  }

  /// @inheritdoc ISharedStrategy
  function getPositionAmounts(
    address nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    (
      ,
      ,
      address token0,
      address token1,
      int24 feeOrTickSpacing,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      ,
      ,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    ) = INFPM(nfpm).positions(tokenId);

    if (liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0) return (0, 0);

    if (liquidity > 0) {
      address pool = _getPool(nfpm, token0, token1, uint24(feeOrTickSpacing));
      (uint160 sqrtPriceX96, , , , , , ) = IUniV3Pool(pool).slot0();
      (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtPriceX96,
        TickMath.getSqrtRatioAtTick(tickLower),
        TickMath.getSqrtRatioAtTick(tickUpper),
        liquidity
      );
    }

    amount0 += tokensOwed0;
    amount1 += tokensOwed1;
  }

  function _getPool(address nfpm, address token0, address token1, uint24 fee) internal view returns (address) {
    address factory = INFPM(nfpm).factory();
    return IUniV3Factory(factory).getPool(token0, token1, fee);
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  function _approveTokens(address[] memory _tokens, uint256[] memory approveAmounts, address target) internal {
    require(_tokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < _tokens.length; ) {
      if (approveAmounts[i] > 0) {
        IERC20(_tokens[i]).safeResetAndApprove(target, approveAmounts[i]);
      }
      unchecked {
        i++;
      }
    }
  }
}
