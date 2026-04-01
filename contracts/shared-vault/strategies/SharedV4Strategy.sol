// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV4UtilsRouter } from "../../private-vault/interfaces/strategies/lpv4/IV4UtilsRouter.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";

/// @dev Minimal IV4Utils types for encoding exitProportional DECREASE_AND_SWAP instructions.
///      Currency = address underneath, so address is used here for ABI-encoding compatibility.
interface IV4Utils {
  enum UtilActions { ADJUST_RANGE, DECREASE_AND_SWAP, COMPOUND }

  struct Instructions {
    UtilActions action;
    bytes params;
  }

  struct DecreaseLiquidityParams {
    uint128 liquidity;
    uint256 deadline;
    uint256 amount0Min;
    uint256 amount1Min;
    bytes hookData;
  }

  struct SwapParams {
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
    uint256 amountOutMin;
    bytes swapData;
  }

  struct DecreaseAndSwapParams {
    DecreaseLiquidityParams decreaseParams;
    SwapParams[] swapParams;
    address swapDestToken;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  function execute(address posm, uint256 tokenId, Instructions calldata instructions) external;
}

/// @title SharedV4Strategy
/// @notice Uniswap V4 LP operations for SharedVault with token validation and position tracking
contract SharedV4Strategy is ISharedStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;
  using PoolIdLibrary for PoolKey;
  using PositionInfoLibrary for PositionInfo;
  using SafeCast for uint256;
  using StateLibrary for IPoolManager;

  address public immutable v4UtilsRouter;

  enum OperationType {
    EXECUTE,
    SAFE_TRANSFER_NFT
  }

  constructor(address _v4UtilsRouter) {
    require(_v4UtilsRouter != address(0), ISharedCommon.ZeroAddress());
    v4UtilsRouter = _v4UtilsRouter;
  }

  /// @inheritdoc ISharedStrategy
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    OperationType opType = abi.decode(data[:32], (OperationType));

    if (opType == OperationType.EXECUTE) {
      return _execute(data[32:]);
    } else if (opType == OperationType.SAFE_TRANSFER_NFT) {
      return _safeTransferNft(data[32:]);
    } else {
      revert ISharedCommon.InvalidOperation();
    }
  }

  function _execute(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      address posm,
      uint256 tokenId,
      bytes memory params,
      uint256 ethValue,
      address[] memory approveTokens,
      uint256[] memory approveAmounts,
      PositionChange[] memory positionChanges
    ) = abi.decode(data, (address, uint256, bytes, uint256, address[], uint256[], PositionChange[]));

    // Validate approved tokens are vault tokens (these are the tokens actually used)
    for (uint256 i; i < approveTokens.length;) {
      if (approveAmounts[i] > 0) {
        _validateVaultToken(approveTokens[i]);
      }
      unchecked { i++; }
    }

    // Also validate position change tokens from on-chain data when adding existing positions
    for (uint256 i; i < positionChanges.length;) {
      if (positionChanges[i].isAdd && positionChanges[i].tokenId != 0) {
        // Verify tokens from actual POSM position data, not caller-supplied values
        IPositionManager pm = IPositionManager(posm);
        (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(positionChanges[i].tokenId);
        address c0 = Currency.unwrap(poolKey.currency0);
        address c1 = Currency.unwrap(poolKey.currency1);
        _validateVaultToken(c0);
        _validateVaultToken(c1);
        positionChanges[i].token0 = c0;
        positionChanges[i].token1 = c1;
      } else {
        if (positionChanges[i].token0 != address(0)) _validateVaultToken(positionChanges[i].token0);
        if (positionChanges[i].token1 != address(0)) _validateVaultToken(positionChanges[i].token1);
      }
      unchecked { i++; }
    }

    // Approve tokens
    require(approveTokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < approveTokens.length;) {
      if (approveAmounts[i] > 0) {
        IERC20(approveTokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
      }
      unchecked { i++; }
    }

    if (tokenId != 0) IERC721(posm).approve(v4UtilsRouter, tokenId);
    IV4UtilsRouter(v4UtilsRouter).execute{ value: ethValue }(posm, params);

    return positionChanges;
  }

  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address posm, uint256 tokenId, bytes memory instruction, PositionChange[] memory positionChanges) = abi.decode(
      data,
      (address, uint256, bytes, PositionChange[])
    );

    // Validate tokens from on-chain POSM data for the position being transferred
    {
      IPositionManager pm = IPositionManager(posm);
      (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
      _validateVaultToken(Currency.unwrap(poolKey.currency0));
      _validateVaultToken(Currency.unwrap(poolKey.currency1));
    }

    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);

    return positionChanges;
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Decreases liquidity proportionally via V4UtilsRouter DECREASE_AND_SWAP (no swap).
  ///      Tokens are swept back to the vault (address(this) in delegatecall context) by V4Utils.
  ///      The NFT is returned to the vault by V4Utils after the decrease regardless of exit type.
  function exitProportional(
    address posm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1
  ) external override returns (PositionChange[] memory changes) {
    IPositionManager pm = IPositionManager(posm);
    uint128 posLiquidity = pm.getPositionLiquidity(tokenId);

    if (posLiquidity == 0) {
      (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(
        false, posm, tokenId,
        Currency.unwrap(poolKey.currency0),
        Currency.unwrap(poolKey.currency1)
      );
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) return new PositionChange[](0);

    bool isFullExit = liquidityToRemove >= posLiquidity;

    IV4Utils.DecreaseAndSwapParams memory decParams = IV4Utils.DecreaseAndSwapParams({
      decreaseParams: IV4Utils.DecreaseLiquidityParams({
        liquidity: liquidityToRemove,
        deadline: block.timestamp,
        amount0Min: minAmount0,
        amount1Min: minAmount1,
        hookData: ""
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      swapDestToken: address(0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    IV4Utils.Instructions memory instructions = IV4Utils.Instructions({
      action: IV4Utils.UtilActions.DECREASE_AND_SWAP,
      params: abi.encode(decParams)
    });

    IERC721(posm).approve(v4UtilsRouter, tokenId);
    IV4UtilsRouter(v4UtilsRouter).execute(
      posm,
      abi.encodeCall(IV4Utils.execute, (posm, tokenId, instructions))
    );

    if (isFullExit) {
      (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(
        false, posm, tokenId,
        Currency.unwrap(poolKey.currency0),
        Currency.unwrap(poolKey.currency1)
      );
    } else {
      changes = new PositionChange[](0);
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Values principal liquidity via `LiquidityAmounts` and current `sqrtPrice` from the v4 PoolManager,
  ///      and uncollected fees via the same `StateLibrary` + fee-growth pattern as v4utils tests (FeeMath).
  function getPositionAmounts(
    address posm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, PositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    uint128 liquidity = pm.getPositionLiquidity(tokenId);
    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();

    IPoolManager manager = pm.poolManager();
    PoolId poolId = poolKey.toId();
    (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolId);

    if (liquidity > 0) {
      (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtPriceX96,
        TickMath.getSqrtPriceAtTick(tickLower),
        TickMath.getSqrtPriceAtTick(tickUpper),
        liquidity
      );
    }

    (uint256 fees0, uint256 fees1) = _uncollectedFees(pm, manager, poolId, tickLower, tickUpper, tokenId);
    amount0 += fees0;
    amount1 += fees1;
  }

  /// @notice Uncollected fees for a v4 position (mirrors v4utils `FeeMath.getFeesOwed` without test-only imports).
  function _uncollectedFees(
    IPositionManager posm,
    IPoolManager manager,
    PoolId poolId,
    int24 tickLower,
    int24 tickUpper,
    uint256 tokenId
  ) private view returns (uint256 fee0, uint256 fee1) {
    (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = manager.getPositionInfo(
      poolId,
      address(posm),
      tickLower,
      tickUpper,
      bytes32(tokenId)
    );
    if (liquidity == 0) return (0, 0);

    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = manager.getFeeGrowthInside(
      poolId,
      tickLower,
      tickUpper
    );

    fee0 = uint256(_feeOwed(feeGrowthInside0X128, feeGrowthInside0LastX128, liquidity));
    fee1 = uint256(_feeOwed(feeGrowthInside1X128, feeGrowthInside1LastX128, liquidity));
  }

  /// @dev Returns fees owed. Uses a defensive check instead of V4 core's unchecked subtraction
  ///      (which relies on uint256 overflow wrapping). This returns 0 on apparent underflow rather
  ///      than risking an incorrect large value if fee growth tracking is out of sync.
  function _feeOwed(
    uint256 feeGrowthInsideX128,
    uint256 feeGrowthInsideLastX128,
    uint256 liquidity
  ) private pure returns (uint128) {
    if (feeGrowthInsideX128 < feeGrowthInsideLastX128 || liquidity == 0) return 0;
    unchecked {
      return FullMath.mulDiv(feeGrowthInsideX128 - feeGrowthInsideLastX128, liquidity, FixedPoint128.Q128).toUint128();
    }
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }
}
