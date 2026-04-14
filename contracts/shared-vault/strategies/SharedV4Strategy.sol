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

import { Permit2Forwarder } from "@uniswap/v4-periphery/src/base/Permit2Forwarder.sol";
import { IPermit2Forwarder } from "@uniswap/v4-periphery/src/interfaces/IPermit2Forwarder.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";

/// @dev Minimal IV4Utils types for encoding exitProportional DECREASE_AND_SWAP instructions.
///      Currency = address underneath, so address is used here for ABI-encoding compatibility.
interface IV4Utils {
  enum UtilActions {
    ADJUST_RANGE,
    DECREASE_AND_SWAP,
    COMPOUND
  }

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

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, posm);
    _validateV4ExecuteCalldataSwapRouters(params, posm, tokenId, cm);

    // Validate approved tokens are vault tokens (these are the tokens actually used)
    for (uint256 i; i < approveTokens.length; ) {
      if (approveAmounts[i] > 0) {
        _validateVaultToken(approveTokens[i]);
      }
      unchecked {
        i++;
      }
    }

    // Also validate position change tokens from on-chain data when adding existing positions
    for (uint256 i; i < positionChanges.length; ) {
      if (positionChanges[i].isAdd && positionChanges[i].tokenId != 0) {
        // Verify tokens from actual POSM position data, not caller-supplied values
        IPositionManager pm = IPositionManager(posm);
        (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(positionChanges[i].tokenId);
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
      unchecked {
        i++;
      }
    }

    // Approve tokens
    require(approveTokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < approveTokens.length; ) {
      if (approveAmounts[i] > 0) {
        IERC20(approveTokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
      }
      unchecked {
        i++;
      }
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

    _requireWhitelistedPosm(posm);

    // Validate tokens from on-chain POSM data for the position being transferred
    {
      IPositionManager pm = IPositionManager(posm);
      (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
      _validateVaultToken(Currency.unwrap(poolKey.currency0));
      _validateVaultToken(Currency.unwrap(poolKey.currency1));
    }

    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);

    return positionChanges;
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Uses `INCREASE_LIQUIDITY_FROM_DELTAS` + `CLOSE_CURRENCY` so the PositionManager computes
  ///      the required liquidity from amounts internally. Any unused tokens are swept back to the vault
  ///      by `CLOSE_CURRENCY` (positive delta = take back). Permit2 approval is set inline.
  function depositProportional(
    address posm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16 // slippageBps unused: V4 INCREASE_LIQUIDITY_FROM_DELTAS has no amountMin parameter
  ) external override {
    if (amount0 == 0 && amount1 == 0) return;

    _requireWhitelistedPosm(posm);

    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
    Currency currency0 = poolKey.currency0;
    Currency currency1 = poolKey.currency1;

    // Guard against silent truncation: token amounts must fit in uint128 (used in INCREASE_LIQUIDITY params).
    // Total ERC20 supply can never exceed uint128.max in practice, but we guard explicitly.
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());

    // Approve via Permit2: vault → Permit2 → PositionManager
    address permit2Addr = address(Permit2Forwarder(address(IPermit2Forwarder(posm))).permit2());
    if (amount0 > 0) {
      address token0 = Currency.unwrap(currency0);
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0) {
      address token1 = Currency.unwrap(currency1);
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }

    // INCREASE_LIQUIDITY_FROM_DELTAS (0x04) + CLOSE_CURRENCY (0x12) for each token
    bytes memory actions = abi.encodePacked(uint8(0x04), uint8(0x12), uint8(0x12));
    bytes[] memory params = new bytes[](3);
    params[0] = abi.encode(tokenId, uint128(amount0), uint128(amount1), bytes(""));
    params[1] = abi.encode(currency0);
    params[2] = abi.encode(currency1);

    pm.modifyLiquidities(abi.encode(actions, params), block.timestamp);
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Decreases liquidity proportionally via V4UtilsRouter DECREASE_AND_SWAP (no swap).
  ///      Tokens are swept back to the vault (address(this) in delegatecall context) by V4Utils.
  ///      The NFT is returned to the vault by V4Utils after the decrease regardless of exit type.
  ///      Protocol fee (platform) and performance fee (vault owner) are forwarded to V4Utils as X64
  ///      values. V4Utils collects them inline rather than via `LpFeeTaker` (no gas fee on exits).
  function exitProportional(
    address posm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 vaultOwnerFeeBasisPoint
  ) external override returns (PositionChange[] memory changes) {
    _requireWhitelistedPosm(posm);

    IPositionManager pm = IPositionManager(posm);
    uint128 posLiquidity = pm.getPositionLiquidity(tokenId);

    if (posLiquidity == 0) {
      (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(
        false,
        posm,
        tokenId,
        Currency.unwrap(poolKey.currency0),
        Currency.unwrap(poolKey.currency1)
      );
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) return new PositionChange[](0);

    bool isFullExit = liquidityToRemove >= posLiquidity;

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    uint64 protocolX64 = SharedStrategyFeeConfig.platformFeeX64(cm, 0);
    uint64 performanceX64 = SharedStrategyFeeConfig.vaultOwnerFeeX64(vaultOwnerFeeBasisPoint);

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
      protocolFeeX64: protocolX64,
      performanceFeeX64: performanceX64,
      gasFeeX64: 0
    });

    IV4Utils.Instructions memory instructions = IV4Utils.Instructions({
      action: IV4Utils.UtilActions.DECREASE_AND_SWAP,
      params: abi.encode(decParams)
    });

    IERC721(posm).approve(v4UtilsRouter, tokenId);
    IV4UtilsRouter(v4UtilsRouter).execute(posm, abi.encodeCall(IV4Utils.execute, (posm, tokenId, instructions)));

    if (isFullExit) {
      (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(
        false,
        posm,
        tokenId,
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
    // Same as `SharedV3Strategy.getPositionAmounts`: the vault invokes this externally, so POSM
    // whitelist cannot use `ISharedVault(address(this))` here. Whitelist is enforced on delegatecall paths.

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

  /// @dev Returns fees owed, matching V4 core's unchecked subtraction pattern.
  ///      Fee growth values are monotonically increasing accumulators that intentionally wrap
  ///      around uint256. When feeGrowthInsideX128 < feeGrowthInsideLastX128 the accumulator
  ///      has wrapped — the correct delta is (type(uint256).max - last + current + 1), which
  ///      is exactly what `unchecked { current - last }` computes in uint256 arithmetic.
  function _feeOwed(
    uint256 feeGrowthInsideX128,
    uint256 feeGrowthInsideLastX128,
    uint256 liquidity
  ) private pure returns (uint128) {
    if (liquidity == 0) return 0;
    unchecked {
      return FullMath.mulDiv(feeGrowthInsideX128 - feeGrowthInsideLastX128, liquidity, FixedPoint128.Q128).toUint128();
    }
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  function _requireWhitelistedPosm(address posm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), posm);
  }

  /// @dev When calldata targets `IV4Utils.execute` with `DECREASE_AND_SWAP`, validates Ox-style routers in each swap step.
  function _validateV4ExecuteCalldataSwapRouters(
    bytes memory params,
    address posm,
    uint256 tokenId,
    ISharedConfigManager cm
  ) private view {
    if (params.length < 4) return;
    if (bytes4(params) != IV4Utils.execute.selector) return;
    bytes memory body = new bytes(params.length - 4);
    for (uint256 j; j < body.length; ) {
      body[j] = params[j + 4];
      unchecked {
        ++j;
      }
    }
    (address p, uint256 tid, IV4Utils.Instructions memory inst) = abi.decode(
      body,
      (address, uint256, IV4Utils.Instructions)
    );
    require(p == posm && tid == tokenId, ISharedCommon.InvalidOperation());
    if (inst.action != IV4Utils.UtilActions.DECREASE_AND_SWAP) return;
    IV4Utils.DecreaseAndSwapParams memory dsp = abi.decode(inst.params, (IV4Utils.DecreaseAndSwapParams));
    for (uint256 i; i < dsp.swapParams.length; ) {
      SharedStrategyGuards.requireWhitelistedOxSwapData(cm, dsp.swapParams[i].swapData);
      unchecked {
        ++i;
      }
    }
  }
}
