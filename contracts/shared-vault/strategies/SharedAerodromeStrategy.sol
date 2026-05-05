// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { INonfungiblePositionManager } from "../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import { ICLFactory } from "../../common/interfaces/protocols/aerodrome/ICLFactory.sol";
import { ICLPool } from "../../common/interfaces/protocols/aerodrome/ICLPool.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
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
      uint256 ethValue
    ) = abi.decode(data, (IV3Utils.SwapAndMintParams, address[], uint256[], uint256));

    _validateVaultToken(params.token0);
    _validateVaultToken(params.token1);
    _requireAerodromeNfpm(params.nfpm);

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    IV3Utils.SwapAndMintResult memory result = IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);

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

    _requireAerodromeNfpm(params.nfpm);
    require(IERC721(params.nfpm).ownerOf(params.tokenId) == address(this), InvalidPoolTokens());

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);

    changes = new PositionChange[](0);
  }

  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address _nfpm, uint256 tokenId, IV3Utils.Instructions memory instructions) = abi.decode(
      data,
      (address, uint256, IV3Utils.Instructions)
    );

    _requireAerodromeNfpm(_nfpm);

    (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);

    instructions.recipient = address(this);
    IERC721(_nfpm).safeTransferFrom(address(this), v3utils, tokenId, abi.encode(instructions));

    if (instructions.whatToDo == IV3Utils.WhatToDo.CHANGE_RANGE) {
      if (!IERC165(_nfpm).supportsInterface(type(IERC721Enumerable).interfaceId)) {
        revert ISharedCommon.NfpmEnumerableRequired();
      }
      IERC721Enumerable e = IERC721Enumerable(_nfpm);
      uint256 n = e.totalSupply();
      require(n > 0, InvalidPoolTokens());
      uint256 newTokenId = e.tokenByIndex(n - 1);
      require(_nfpmNftOwnedByVault(_nfpm, newTokenId), InvalidPoolTokens());
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      changes[1] = PositionChange(true, _nfpm, newTokenId, token0, token1);
    } else if (!_nfpmNftOwnedByVault(_nfpm, tokenId)) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
    } else {
      (, , , , , , , uint128 liqAfter, , , , ) = INonfungiblePositionManager(_nfpm).positions(tokenId);
      if (liqAfter == 0) {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
      } else {
        changes = new PositionChange[](0);
      }
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
    address pool = _getPool(_nfpm, token0, token1, tickSpacing);
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
  function exitProportional(
    address _nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 vaultOwnerFeeBasisPoint
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

    if (isFullExit) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, _nfpm, tokenId, token0, token1);
    } else {
      changes = new PositionChange[](0);
    }
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
  ///      Aerodrome tickSpacing-based pool lookup.
  function _positionAmountsSplit(
    address _nfpm,
    uint256 tokenId
  ) private view returns (uint256 principal0, uint256 principal1, uint128 tokensOwed0, uint128 tokensOwed1) {
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
      uint128 owed0,
      uint128 owed1
    ) = INonfungiblePositionManager(_nfpm).positions(tokenId);

    tokensOwed0 = owed0;
    tokensOwed1 = owed1;

    if (liquidity == 0) return (0, 0, tokensOwed0, tokensOwed1);

    address pool = _getPool(_nfpm, token0, token1, tickSpacing);
    (uint160 sqrtPriceX96, , , , , ) = ICLPool(pool).slot0();
    (principal0, principal1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      liquidity
    );
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
  }

  function _getPool(address _nfpm, address token0, address token1, int24 tickSpacing) internal view returns (address) {
    address factory = INonfungiblePositionManager(_nfpm).factory();
    return ICLFactory(factory).getPool(token0, token1, tickSpacing);
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  function _approveTokens(address[] memory _tokens, uint256[] memory approveAmounts, address target) internal {
    require(_tokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < _tokens.length; ) {
      if (approveAmounts[i] > 0) {
        _validateVaultToken(_tokens[i]);
        IERC20(_tokens[i]).safeResetAndApprove(target, approveAmounts[i]);
      }
      unchecked {
        i++;
      }
    }
  }

  function _nfpmNftOwnedByVault(address _nfpm, uint256 id) private view returns (bool) {
    try IERC721(_nfpm).ownerOf(id) returns (address owner) {
      return owner == address(this);
    } catch {
      return false;
    }
  }

  function _requireAerodromeNfpm(address _nfpm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), _nfpm);
  }
}
