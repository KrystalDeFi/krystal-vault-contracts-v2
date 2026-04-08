// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { ICLGauge } from "../../common/interfaces/protocols/aerodrome/ICLGauge.sol";
import { INonfungiblePositionManager } from "../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import { ICLGaugeFactory } from "../../common/interfaces/protocols/aerodrome/ICLGaugeFactory.sol";
import { ICLFactory } from "../../common/interfaces/protocols/aerodrome/ICLFactory.sol";
import { ICLPool } from "../../common/interfaces/protocols/aerodrome/ICLPool.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CollectFee } from "../../private-vault/libraries/CollectFee.sol";

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

/// @title SharedAerodromeStrategy
/// @notice Aerodrome CL LP + gauge farming for SharedVault with token validation and position tracking
contract SharedAerodromeStrategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable v3utils;
  address public immutable lpFeeTaker;
  address public immutable gaugeFactory;
  address public immutable nfpm;
  ISharedConfigManager public immutable configManager;

  enum OperationType {
    SWAP_AND_MINT,
    SWAP_AND_INCREASE,
    SAFE_TRANSFER_NFT,
    DEPOSIT_GAUGE,
    WITHDRAW_GAUGE,
    HARVEST_GAUGE
  }

  constructor(address _v3utils, address _lpFeeTaker, address _gaugeFactory, address _configManager) {
    require(
      _v3utils != address(0) &&
        _lpFeeTaker != address(0) &&
        _gaugeFactory != address(0) &&
        _configManager != address(0),
      ISharedCommon.ZeroAddress()
    );
    v3utils = _v3utils;
    lpFeeTaker = _lpFeeTaker;
    gaugeFactory = _gaugeFactory;
    nfpm = ICLGaugeFactory(_gaugeFactory).nft();
    configManager = ISharedConfigManager(_configManager);
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
    } else if (opType == OperationType.DEPOSIT_GAUGE) {
      _depositGauge(data[32:]);
      return new PositionChange[](0);
    } else if (opType == OperationType.WITHDRAW_GAUGE) {
      _withdrawGauge(data[32:]);
      return new PositionChange[](0);
    } else if (opType == OperationType.HARVEST_GAUGE) {
      _harvestGauge(data[32:]);
      return new PositionChange[](0);
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

    params.protocolFeeX64 = SharedStrategyFeeConfig.platformFeeX64(configManager, platformFeeBasisPointOverride);
    params.gasFeeX64 = gasFeeX64Override;

    IV3Utils.SwapAndMintResult memory result = IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);

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

    params.protocolFeeX64 = SharedStrategyFeeConfig.platformFeeX64(configManager, platformFeeBasisPointOverride);
    params.gasFeeX64 = gasFeeX64Override;

    IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);

    changes = new PositionChange[](0);
  }

  /// @dev For CHANGE_RANGE: caller must provide newTokenId (the NFT minted by V3Utils for the new position).
  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      address _nfpm,
      uint256 tokenId,
      IV3Utils.Instructions memory instructions,
      bool isFullWithdraw,
      uint256 newTokenId,
      uint16 platformFeeBasisPointOverride,
      uint64 gasFeeX64Override
    ) = abi.decode(data, (address, uint256, IV3Utils.Instructions, bool, uint256, uint16, uint64));

    instructions.recipient = address(this);
    instructions.performanceFeeX64 = SharedStrategyFeeConfig.platformFeeX64(
      configManager,
      platformFeeBasisPointOverride
    );
    instructions.gasFeeX64 = gasFeeX64Override;
    IERC721(_nfpm).safeTransferFrom(address(this), v3utils, tokenId, abi.encode(instructions));

    if (instructions.whatToDo == IV3Utils.WhatToDo.CHANGE_RANGE) {
      (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
      require(newTokenId != 0, InvalidPoolTokens());
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      changes[1] = PositionChange(true, _nfpm, newTokenId, token0, token1);
    } else if (isFullWithdraw) {
      (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
  }

  function _depositGauge(bytes calldata data) internal {
    uint256 tokenId = abi.decode(data, (uint256));
    require(tokenId != 0, InvalidPoolTokens());

    address clGauge = _getGaugeFromTokenId(tokenId);
    IERC721(nfpm).approve(clGauge, tokenId);
    ICLGauge(clGauge).deposit(tokenId);
  }

  function _withdrawGauge(bytes calldata data) internal {
    (uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) = abi.decode(data, (uint256, uint64, uint64));

    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvestRewards(clGauge, tokenId, rewardFeeX64, gasFeeX64);
    ICLGauge(clGauge).withdraw(tokenId);
  }

  function _harvestGauge(bytes calldata data) internal {
    (uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) = abi.decode(data, (uint256, uint64, uint64));

    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvestRewards(clGauge, tokenId, rewardFeeX64, gasFeeX64);
  }

  function _harvestRewards(address clGauge, uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal {
    address rewardToken = ICLGauge(clGauge).rewardToken();
    uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

    ICLGauge(clGauge).getReward(tokenId);

    uint256 balanceAfter = IERC20(rewardToken).balanceOf(address(this));
    if (balanceAfter <= balanceBefore) return;

    uint256 harvestedAmount = balanceAfter - balanceBefore;
    uint256 feeAmount;

    if (rewardFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(),
        rewardToken,
        harvestedAmount,
        rewardFeeX64,
        CollectFee.FeeType.FARM_REWARD
      );
    }

    if (gasFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(),
        rewardToken,
        harvestedAmount,
        gasFeeX64,
        CollectFee.FeeType.GAS
      );
    }
  }

  function _decreaseVaultPosition(
    address _nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 minAmount0,
    uint256 minAmount1,
    address token0,
    address token1,
    int24 tickSpacing,
    uint16 vaultOwnerFeeBasisPoint
  ) internal {
    address pool = _getPool(token0, token1, tickSpacing);
    ICommon.FeeConfig memory perfFee = SharedStrategyFeeConfig.performanceFeeConfig(vaultOwnerFeeBasisPoint);
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
  /// @dev Handles gauge-staked and direct positions. Proportional exit: NFPM + `LpFeeTaker` (public LpStrategy pattern).
  function exitProportional(
    address _nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 vaultOwnerFeeBasisPoint
  ) external override returns (PositionChange[] memory changes) {
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

    bool isStaked = IERC721(_nfpm).ownerOf(tokenId) != address(this);
    address clGauge;

    if (isStaked) {
      clGauge = _getGaugeFromTokenId(tokenId);
      _harvestRewards(clGauge, tokenId, 0, 0);
      ICLGauge(clGauge).withdraw(tokenId);
    }

    if (posLiquidity == 0) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) {
      if (isStaked) {
        IERC721(_nfpm).approve(clGauge, tokenId);
        ICLGauge(clGauge).deposit(tokenId);
      }
      return new PositionChange[](0);
    }

    bool isFullExit = liquidityToRemove >= posLiquidity;

    _decreaseVaultPosition(
      _nfpm,
      tokenId,
      liquidityToRemove,
      minAmount0,
      minAmount1,
      token0,
      token1,
      tickSpacing,
      vaultOwnerFeeBasisPoint
    );

    if (!isFullExit && isStaked) {
      IERC721(_nfpm).approve(clGauge, tokenId);
      ICLGauge(clGauge).deposit(tokenId);
    }

    if (isFullExit) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
  }

  /// @inheritdoc ISharedStrategy
  function getPositionAmounts(
    address _nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    (
      ,
      ,
      address token0,
      address token1,
      int24 tickSpacing,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      ,
      ,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    ) = INonfungiblePositionManager(_nfpm).positions(tokenId);

    if (liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0) return (0, 0);

    if (liquidity > 0) {
      address pool = _getPool(token0, token1, tickSpacing);
      (uint160 sqrtPriceX96, , , , , ) = ICLPool(pool).slot0();
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

  /// @inheritdoc ISharedStrategy
  /// @dev If the NFT is staked in a gauge (held by the gauge contract, not by the vault),
  ///      increaseLiquidity is not possible — skip silently so tokens remain idle.
  function depositProportional(address _nfpm, uint256 tokenId, uint256 amount0, uint256 amount1) external override {
    if (amount0 == 0 && amount1 == 0) return;
    if (IERC721(_nfpm).ownerOf(tokenId) != address(this)) return;
    (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
    if (amount0 > 0) IERC20(token0).safeResetAndApprove(_nfpm, amount0);
    if (amount1 > 0) IERC20(token1).safeResetAndApprove(_nfpm, amount1);
    INonfungiblePositionManager(_nfpm).increaseLiquidity(
      INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function _getPool(address token0, address token1, int24 tickSpacing) internal view returns (address) {
    address factory = INonfungiblePositionManager(nfpm).factory();
    return ICLFactory(factory).getPool(token0, token1, tickSpacing);
  }

  function _getGaugeFromTokenId(uint256 tokenId) internal view returns (address gauge) {
    (, , address token0, address token1, int24 tickSpacing, , , , , , , ) = INonfungiblePositionManager(nfpm).positions(
      tokenId
    );
    if (token0 > token1) (token0, token1) = (token1, token0);
    address factory = INonfungiblePositionManager(nfpm).factory();
    address pool = ICLFactory(factory).getPool(token0, token1, tickSpacing);
    require(pool != address(0), InvalidPoolTokens());
    gauge = ICLPool(pool).gauge();
    require(gauge != address(0), InvalidPoolTokens());
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
