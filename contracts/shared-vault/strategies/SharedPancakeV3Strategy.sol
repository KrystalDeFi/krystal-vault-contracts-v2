// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { IMasterChefV3 } from "../../common/interfaces/protocols/pancakev3/IMasterChefV3.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CollectFee } from "../../private-vault/libraries/CollectFee.sol";

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";

/// @dev Generic NFPM for querying positions
interface INFPM {
  function positions(uint256 tokenId)
    external
    view
    returns (
      uint96, address, address token0, address token1, int24 feeOrTickSpacing,
      int24 tickLower, int24 tickUpper, uint128 liquidity, uint256, uint256, uint128, uint128
    );
  function factory() external view returns (address);
}

/// @dev V3 factory for pool lookup (fee as uint24)
interface IUniV3Factory {
  function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

/// @dev V3 pool for slot0 query
interface IV3Pool {
  function slot0()
    external
    view
    returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
}

/// @title SharedPancakeV3Strategy
/// @notice PancakeSwap V3 LP + MasterChef farming for SharedVault with token validation and position tracking
contract SharedPancakeV3Strategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable v3utils;
  address public immutable masterChefV3;
  ISharedConfigManager public immutable configManager;

  enum OperationType {
    SWAP_AND_MINT,
    SWAP_AND_INCREASE,
    SAFE_TRANSFER_NFT,
    DEPOSIT_MASTERCHEF,
    WITHDRAW_MASTERCHEF,
    HARVEST_MASTERCHEF
  }

  constructor(address _v3utils, address _masterChefV3, address _configManager) {
    require(_v3utils != address(0) && _masterChefV3 != address(0) && _configManager != address(0), ISharedCommon.ZeroAddress());
    v3utils = _v3utils;
    masterChefV3 = _masterChefV3;
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
    } else if (opType == OperationType.DEPOSIT_MASTERCHEF) {
      _depositMasterChef(data[32:]);
      return new PositionChange[](0);
    } else if (opType == OperationType.WITHDRAW_MASTERCHEF) {
      _withdrawMasterChef(data[32:]);
      return new PositionChange[](0);
    } else if (opType == OperationType.HARVEST_MASTERCHEF) {
      _harvestMasterChef(data[32:]);
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
      uint256 ethValue
    ) = abi.decode(data, (IV3Utils.SwapAndMintParams, address[], uint256[], uint256));

    _validateVaultToken(params.token0);
    _validateVaultToken(params.token1);

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    IV3Utils.SwapAndMintResult memory result = IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);

    // Get pool for position tracking
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, params.nfpm, result.tokenId, params.token0, params.token1);
  }

  function _swapAndIncreaseLiquidity(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      IV3Utils.SwapAndIncreaseLiquidityParams memory params,
      address[] memory approveTokens,
      uint256[] memory approveAmounts,
      uint256 ethValue
    ) = abi.decode(data, (IV3Utils.SwapAndIncreaseLiquidityParams, address[], uint256[], uint256));

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);

    changes = new PositionChange[](0);
  }

  /// @dev For CHANGE_RANGE: caller must provide newTokenId (the NFT minted by V3Utils for the new position).
  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address _nfpm, uint256 tokenId, IV3Utils.Instructions memory instructions, bool isFullWithdraw, uint256 newTokenId) =
      abi.decode(data, (address, uint256, IV3Utils.Instructions, bool, uint256));

    instructions.recipient = address(this);
    IERC721(_nfpm).safeTransferFrom(address(this), v3utils, tokenId, abi.encode(instructions));

    if (instructions.whatToDo == IV3Utils.WhatToDo.CHANGE_RANGE) {
      (,, address token0, address token1,,,,,,,,) = INFPM(_nfpm).positions(tokenId);
      require(newTokenId != 0, InvalidPoolTokens());
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      changes[1] = PositionChange(true, _nfpm, newTokenId, token0, token1);
    } else if (isFullWithdraw) {
      (,, address token0, address token1,,,,,,,,) = INFPM(_nfpm).positions(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
  }

  function _depositMasterChef(bytes calldata data) internal {
    uint256 tokenId = abi.decode(data, (uint256));
    require(tokenId != 0, InvalidPoolTokens());

    address _nfpm = IMasterChefV3(masterChefV3).nonfungiblePositionManager();
    IERC721(_nfpm).safeTransferFrom(address(this), masterChefV3, tokenId);
  }

  function _withdrawMasterChef(bytes calldata data) internal {
    (uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) = abi.decode(data, (uint256, uint64, uint64));

    _harvestRewards(tokenId, rewardFeeX64, gasFeeX64);
    IMasterChefV3(masterChefV3).withdraw(tokenId, address(this));
  }

  function _harvestMasterChef(bytes calldata data) internal {
    (uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) = abi.decode(data, (uint256, uint64, uint64));

    _harvestRewards(tokenId, rewardFeeX64, gasFeeX64);
  }

  function _harvestRewards(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal {
    address rewardToken = IMasterChefV3(masterChefV3).CAKE();
    uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

    IMasterChefV3(masterChefV3).harvest(tokenId, address(this));

    uint256 balanceAfter = IERC20(rewardToken).balanceOf(address(this));
    if (balanceAfter <= balanceBefore) return;

    uint256 harvestedAmount = balanceAfter - balanceBefore;
    uint256 feeAmount;

    if (rewardFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(), rewardToken, harvestedAmount, rewardFeeX64, CollectFee.FeeType.FARM_REWARD
      );
    }

    if (gasFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(), rewardToken, harvestedAmount, gasFeeX64, CollectFee.FeeType.GAS
      );
    }
  }

  /// @inheritdoc ISharedStrategy
  function getPositionAmounts(address _nfpm, uint256 tokenId)
    external
    view
    override
    returns (uint256 amount0, uint256 amount1)
  {
    (,, address token0, address token1, int24 feeOrTickSpacing,
      int24 tickLower, int24 tickUpper, uint128 liquidity,,,
      uint128 tokensOwed0, uint128 tokensOwed1) = INFPM(_nfpm).positions(tokenId);

    if (liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0) return (0, 0);

    if (liquidity > 0) {
      address pool = _getPool(_nfpm, token0, token1, uint24(feeOrTickSpacing));
      (uint160 sqrtPriceX96,,,,,,) = IV3Pool(pool).slot0();
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

  function _getPool(address _nfpm, address token0, address token1, uint24 fee)
    internal
    view
    returns (address)
  {
    address factory = INFPM(_nfpm).factory();
    return IUniV3Factory(factory).getPool(token0, token1, fee);
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  function _approveTokens(address[] memory _tokens, uint256[] memory approveAmounts, address target) internal {
    require(_tokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < _tokens.length;) {
      if (approveAmounts[i] > 0) {
        IERC20(_tokens[i]).safeResetAndApprove(target, approveAmounts[i]);
      }
      unchecked { i++; }
    }
  }
}
