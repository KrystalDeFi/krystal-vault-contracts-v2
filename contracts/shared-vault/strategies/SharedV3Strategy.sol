// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
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
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { SharedNfpmProportionalExit } from "../libraries/SharedNfpmProportionalExit.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";

/// @title SharedV3Strategy
/// @notice Uniswap V3 LP operations for SharedVault with token validation and position tracking
contract SharedV3Strategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable v3utils;
  address public immutable lpFeeTaker;

  uint256 private constant Q128 = 0x100000000000000000000000000000000;

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

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, params.nfpm);

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    IV3Utils.SwapAndMintResult memory result = IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);
    _revokeTokenApprovals(approveTokens, approveAmounts, v3utils);

    // Return position change: new position added
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

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, params.nfpm);
    require(IERC721(params.nfpm).ownerOf(params.tokenId) == address(this), InvalidPoolTokens());

    _approveTokens(approveTokens, approveAmounts, v3utils);
    params.recipient = address(this);

    IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);
    _revokeTokenApprovals(approveTokens, approveAmounts, v3utils);

    // No position change — existing position updated, already tracked
    changes = new PositionChange[](0);
  }

  /// @dev `CHANGE_RANGE`: Detects the newly minted token via `tokenOfOwnerByIndex(address(this), balanceBefore - 1)`.
  ///      **Assumed V3Utils ordering**: mints the new NFT to the vault first, THEN returns the old one.
  ///      With this ordering the new token lands at owner-index `balanceBefore - 1` (appended while the old token
  ///      is still absent), and the old token lands at `balanceBefore` after being returned.
  ///      If a future V3Utils version returns the old NFT BEFORE minting the new one, the old token occupies
  ///      index `balanceBefore - 1` and the check below (`newTokenId != tokenId`) catches the inversion.
  ///      A post-call balance check enforces exactly one NFT was minted (mirrors SharedV4Strategy's guard).
  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, IV3Utils.Instructions memory instructions) = abi.decode(
      data,
      (address, uint256, IV3Utils.Instructions)
    );

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);

    (, , address token0, address token1, , , , , , , , ) = INFPM(nfpm).positions(tokenId);

    instructions.recipient = address(this);

    // Snapshot vault's NFT count before the transfer so we can locate the new token after CHANGE_RANGE.
    uint256 balanceBefore = IERC721(nfpm).balanceOf(address(this));

    IERC721(nfpm).safeTransferFrom(address(this), v3utils, tokenId, abi.encode(instructions));

    if (instructions.whatToDo == IV3Utils.WhatToDo.CHANGE_RANGE) {
      if (!IERC165(nfpm).supportsInterface(type(IERC721Enumerable).interfaceId)) {
        revert ISharedCommon.NfpmEnumerableRequired();
      }
      // V3Utils mints exactly one new NFT then returns the old NFT → post-call balance must be balanceBefore + 1.
      // This mirrors SharedV4Strategy's nextTokenId guard, catching any future multi-mint V3Utils version.
      require(balanceBefore > 0, InvalidPoolTokens());
      require(IERC721(nfpm).balanceOf(address(this)) == balanceBefore + 1, InvalidPoolTokens());
      uint256 newTokenId = IERC721Enumerable(nfpm).tokenOfOwnerByIndex(address(this), balanceBefore - 1);
      // Guard against inverted ordering (old returned before new minted): in that case the resolved
      // index holds the original tokenId, not a newly minted position.
      require(newTokenId != tokenId, InvalidPoolTokens());
      require(_nfpmNftOwnedByVault(nfpm, newTokenId), InvalidPoolTokens());
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
      changes[1] = PositionChange(true, nfpm, newTokenId, token0, token1);
    } else if (!_nfpmNftOwnedByVault(nfpm, tokenId)) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
    } else {
      (, , , , , , , uint128 liqAfter, , , , ) = INFPM(nfpm).positions(tokenId);
      if (liqAfter == 0) {
        changes = new PositionChange[](1);
        changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
      } else {
        changes = new PositionChange[](0);
      }
    }
  }

  /// @inheritdoc ISharedStrategy
  function collectFees(address nfpm, uint256 tokenId, uint16 vaultOwnerFeeBasisPoint) external override {
    (, , address token0, address token1, uint24 fee, , , , , , , ) = INFPM(nfpm).positions(tokenId);
    address pool = _getPool(nfpm, token0, token1, fee);
    ICommon.FeeConfig memory perfFee = SharedStrategyFeeConfig.performanceFeeConfig(vaultOwnerFeeBasisPoint);
    SharedNfpmProportionalExit.collectAccumulatedFees(nfpm, tokenId, token0, token1, pool, lpFeeTaker, perfFee);
  }

  function _decreaseVaultPosition(
    address nfpm,
    uint256 tokenId,
    uint128 liquidityToRemove,
    uint256 minAmount0,
    uint256 minAmount1,
    address token0,
    address token1,
    uint24 fee,
    uint16 vaultOwnerFeeBasisPoint
  ) internal {
    address pool = _getPool(nfpm, token0, token1, fee);
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
    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);

    (, , address token0, address token1, uint24 fee, , , uint128 posLiquidity, , , , ) = INFPM(nfpm).positions(tokenId);

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
      fee,
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

    (uint256 principal0, uint256 principal1, uint128 tokensOwed0, uint128 tokensOwed1) = _positionAmountsSplit(
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
  ) private view returns (uint256 principal0, uint256 principal1, uint128 tokensOwed0, uint128 tokensOwed1) {
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
      IUniswapV3Pool(pool), tickLower, tickUpper, tick
    );
    unchecked {
      tokensOwed0 += uint128(FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, Q128));
      tokensOwed1 += uint128(FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, Q128));
    }
  }

  function _getFeeGrowthInside(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) private view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    unchecked {
      (,, uint256 lowerFg0Outside, uint256 lowerFg1Outside,,,,) = pool.ticks(tickLower);
      (,, uint256 upperFg0Outside, uint256 upperFg1Outside,,,,) = pool.ticks(tickUpper);
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

  function _revokeTokenApprovals(address[] memory _tokens, uint256[] memory approveAmounts, address target) internal {
    for (uint256 i; i < _tokens.length; ) {
      if (approveAmounts[i] > 0 && _tokens[i] != address(0)) IERC20(_tokens[i]).safeApprove(target, 0);
      unchecked { i++; }
    }
  }

  function _nfpmNftOwnedByVault(address nfpm, uint256 id) private view returns (bool) {
    try IERC721(nfpm).ownerOf(id) returns (address owner) {
      return owner == address(this);
    } catch {
      return false;
    }
  }
}
