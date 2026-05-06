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
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";

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

  uint256 private constant _FEE_Q64 = 0x10000000000000000;

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
      uint256[] memory approveAmounts
    ) = abi.decode(data, (address, uint256, bytes, uint256, address[], uint256[]));

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, posm);
    _validateV4ExecuteCalldataSwapRouters(params, posm, tokenId);

    // Validate approved tokens are vault tokens
    require(approveTokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    for (uint256 i; i < approveTokens.length; ) {
      if (approveAmounts[i] > 0) {
        _validateVaultToken(approveTokens[i]);
        IERC20(approveTokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
      }
      unchecked {
        i++;
      }
    }

    IPositionManager pm = IPositionManager(posm);

    // Snapshot next tokenId before the call to detect newly minted positions
    uint256 nextIdBefore = pm.nextTokenId();

    if (tokenId != 0) IERC721(posm).approve(v4UtilsRouter, tokenId);
    IV4UtilsRouter(v4UtilsRouter).execute{ value: ethValue }(posm, params);

    // Revoke residual token allowances: the utility may have consumed less than approved.
    for (uint256 i; i < approveTokens.length; ) {
      if (approveAmounts[i] > 0) IERC20(approveTokens[i]).safeApprove(v4UtilsRouter, 0);
      unchecked { i++; }
    }

    // Compute position changes from on-chain state — never trust caller-supplied values
    if (tokenId == 0) {
      // New mint: require exactly one position was minted to avoid untracked vault positions.
      require(pm.nextTokenId() == nextIdBefore + 1, InvalidPoolTokens());
      uint256 newId = nextIdBefore;
      require(_posmNftOwnedByVault(posm, newId), InvalidPoolTokens());
      (PoolKey memory key, ) = pm.getPoolAndPositionInfo(newId);
      address c0 = Currency.unwrap(key.currency0);
      address c1 = Currency.unwrap(key.currency1);
      _validateVaultToken(c0);
      _validateVaultToken(c1);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(true, posm, newId, c0, c1);
    } else if (
      pm.nextTokenId() > nextIdBefore &&
      _posmNftOwnedByVault(posm, nextIdBefore) &&
      pm.getPositionLiquidity(tokenId) == 0
    ) {
      // ADJUST_RANGE: require exactly one new position so no vault-owned NFTs go untracked.
      require(pm.nextTokenId() == nextIdBefore + 1, InvalidPoolTokens());
      (PoolKey memory oldKey, ) = pm.getPoolAndPositionInfo(tokenId);
      (PoolKey memory newKey, ) = pm.getPoolAndPositionInfo(nextIdBefore);
      changes = new PositionChange[](2);
      changes[0] = PositionChange(
        false,
        posm,
        tokenId,
        Currency.unwrap(oldKey.currency0),
        Currency.unwrap(oldKey.currency1)
      );
      changes[1] = PositionChange(
        true,
        posm,
        nextIdBefore,
        Currency.unwrap(newKey.currency0),
        Currency.unwrap(newKey.currency1)
      );
    } else if (pm.getPositionLiquidity(tokenId) == 0) {
      // Full exit: liquidity drained to zero
      (PoolKey memory key, ) = pm.getPoolAndPositionInfo(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, posm, tokenId, Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
    } else {
      // Partial decrease, compound, or increase — no tracked position change
      changes = new PositionChange[](0);
    }
  }

  function _safeTransferNft(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address posm, uint256 tokenId, bytes memory instruction) = abi.decode(data, (address, uint256, bytes));

    _requireWhitelistedPosm(posm);

    IPositionManager pm = IPositionManager(posm);

    // Read tokens and snapshot nextTokenId before transferring
    (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
    address c0 = Currency.unwrap(poolKey.currency0);
    address c1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(c0);
    _validateVaultToken(c1);
    uint256 nextIdBefore = pm.nextTokenId();

    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);

    // Compute position changes from on-chain state after the transfer
    if (
      pm.nextTokenId() > nextIdBefore &&
      _posmNftOwnedByVault(posm, nextIdBefore) &&
      pm.getPositionLiquidity(tokenId) == 0
    ) {
      // ADJUST_RANGE: require exactly one new position so no vault-owned NFTs go untracked.
      require(pm.nextTokenId() == nextIdBefore + 1, InvalidPoolTokens());
      (PoolKey memory newKey, ) = pm.getPoolAndPositionInfo(nextIdBefore);
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, posm, tokenId, c0, c1);
      changes[1] = PositionChange(
        true,
        posm,
        nextIdBefore,
        Currency.unwrap(newKey.currency0),
        Currency.unwrap(newKey.currency1)
      );
    } else if (!_posmNftOwnedByVault(posm, tokenId) || pm.getPositionLiquidity(tokenId) == 0) {
      // Full exit: vault no longer holds the NFT, or position liquidity is zero
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, posm, tokenId, c0, c1);
    } else {
      // Partial or non-exit operation — position still active, no tracking change
      changes = new PositionChange[](0);
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Uses `INCREASE_LIQUIDITY_FROM_DELTAS` + `CLOSE_CURRENCY` so the PositionManager computes
  ///      the required liquidity from amounts internally. Any unused tokens are swept back to the vault
  ///      by `CLOSE_CURRENCY` (positive delta = take back). Permit2 approval is set inline.
  ///      Slippage is enforced via a pre/post `getPositionLiquidity` comparison: expected liquidity is
  ///      derived from `LiquidityAmounts.getLiquidityForAmounts` at the pre-call sqrtPrice; if the
  ///      actual liquidity added falls below `expectedLiquidity * (1 - slippageBps / 10000)`, reverts.
  function depositProportional(
    address posm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16 slippageBps
  ) external override {
    if (amount0 == 0 && amount1 == 0) return;

    _requireWhitelistedPosm(posm);

    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, PositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    Currency currency0 = poolKey.currency0;
    Currency currency1 = poolKey.currency1;

    // Guard against silent truncation: token amounts must fit in uint128 (used in INCREASE_LIQUIDITY params).
    // Total ERC20 supply can never exceed uint128.max in practice, but we guard explicitly.
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());

    // Capture pre-deposit state for slippage check (only when slippage protection requested)
    uint128 liquidityBefore;
    uint160 sqrtPriceX96;
    if (slippageBps > 0) {
      liquidityBefore = pm.getPositionLiquidity(tokenId);
      (sqrtPriceX96, , , ) = pm.poolManager().getSlot0(poolKey.toId());
    }

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

    // Clear residual ERC20 → Permit2 and Permit2 → posm allowances. The PositionManager may
    // consume less than amount0/amount1 (e.g. when only one side of the range is used), leaving
    // a dangling allowance that could be exploited within the Permit2 expiry window.
    if (amount0 > 0) {
      address token0 = Currency.unwrap(currency0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, 0, 0);
      IERC20(token0).safeApprove(permit2Addr, 0);
    }
    if (amount1 > 0) {
      address token1 = Currency.unwrap(currency1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, 0, 0);
      IERC20(token1).safeApprove(permit2Addr, 0);
    }

    // Slippage check: compare actual liquidity added to expected minimum
    if (slippageBps > 0) {
      uint128 liquidityAdded = pm.getPositionLiquidity(tokenId) - liquidityBefore;
      int24 tickLower = positionInfo.tickLower();
      int24 tickUpper = positionInfo.tickUpper();
      uint128 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
        sqrtPriceX96,
        TickMath.getSqrtPriceAtTick(tickLower),
        TickMath.getSqrtPriceAtTick(tickUpper),
        amount0,
        amount1
      );
      uint128 minLiquidity = uint128(FullMath.mulDiv(expectedLiquidity, 10_000 - slippageBps, 10_000));
      require(liquidityAdded >= minLiquidity, ISharedCommon.InsufficientOutput());
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Collects accumulated fees via DECREASE_LIQUIDITY(0) + CLOSE_CURRENCY × 2 — a zero-liquidity
  ///      decrease syncs fee growth without touching principal; CLOSE_CURRENCY sweeps accumulated fees
  ///      to the vault (address(this) in delegatecall context). Performance and platform fees are
  ///      then applied inline since V4Strategy has no dedicated lpFeeTaker.
  ///      Native ETH positions (Currency.unwrap == address(0)) are rejected at position-add time by
  ///      _validateVaultToken, so this function is never called for native-currency pools.
  function collectFees(address posm, uint256 tokenId, uint16 vaultOwnerFeeBasisPoint) external override {
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);

    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    // DECREASE_LIQUIDITY(0x01) with liquidity=0 syncs fee growth and creates a collectible delta.
    // CLOSE_CURRENCY(0x12) sweeps the positive delta (accumulated fees) to address(this).
    bytes memory actions = abi.encodePacked(uint8(0x01), uint8(0x12), uint8(0x12));
    bytes[] memory collectParams = new bytes[](3);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), bytes(""));
    collectParams[1] = abi.encode(poolKey.currency0);
    collectParams[2] = abi.encode(poolKey.currency1);
    pm.modifyLiquidities(abi.encode(actions, collectParams), block.timestamp);

    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (collected0 == 0 && collected1 == 0) return;

    ICommon.FeeConfig memory fc = SharedStrategyFeeConfig.performanceFeeConfig(vaultOwnerFeeBasisPoint);
    _applyFees(token0, collected0, token1, collected1, fc);
  }

  /// @dev V3/Aerodrome route fees through `LpFeeTaker.takeFees`, which encapsulates approval + split.
  ///      V4 reimplements the split inline because V4Utils integration with LpFeeTaker does not exist:
  ///      the V4 PositionManager uses Permit2 approvals and its own settlement flow, making the
  ///      LpFeeTaker approval-then-call pattern incompatible. Any future fee-policy change must be
  ///      applied here in addition to LpFeeTaker. Gas fee is intentionally omitted (exits handle it
  ///      via V4UtilsRouter's `gasFeeX64`; pre-collect is perf/platform only).
  function _applyFees(address token0, uint256 amount0, address token1, uint256 amount1, ICommon.FeeConfig memory fc) private {
    if (fc.platformFeeBasisPoint > 0 && fc.platformFeeRecipient != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.platformFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.platformFeeBasisPoint, 10_000);
      if (fee0 > 0) IERC20(token0).safeTransfer(fc.platformFeeRecipient, fee0);
      if (fee1 > 0) IERC20(token1).safeTransfer(fc.platformFeeRecipient, fee1);
    }
    if (fc.vaultOwnerFeeBasisPoint > 0 && fc.vaultOwner != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.vaultOwnerFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.vaultOwnerFeeBasisPoint, 10_000);
      if (fee0 > 0) IERC20(token0).safeTransfer(fc.vaultOwner, fee0);
      if (fee1 > 0) IERC20(token1).safeTransfer(fc.vaultOwner, fee1);
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Decreases liquidity proportionally via V4UtilsRouter DECREASE_AND_SWAP (no swap).
  ///      Tokens are swept back to the vault (address(this) in delegatecall context) by V4Utils.
  ///      The NFT is returned to the vault by V4Utils after the decrease regardless of exit type.
  ///      Fees on accumulated LP income are handled in collectFees (pre-collect) — not charged here
  ///      on principal, to match V3/Aerodrome which only takes gas fees on proportional exits.
  function exitProportional(
    address posm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 /* vaultOwnerFeeBasisPoint */
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
      // Fees on accumulated LP income are handled in collectFees (pre-collect before idle snapshot).
      // Charging protocol/performance fees again on the principal returned here would double-charge
      // withdrawers relative to V3/Aerodrome, which only takes gas fees on principal exits.
      protocolFeeX64: 0,
      performanceFeeX64: 0,
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
  ///      Same external-call pattern as `SharedV3Strategy` / Aerodrome / Pancake `getPositionAmounts`:
  ///      no POSM whitelist here; POSM allowlist is enforced on delegatecall paths and when the vault tracks positions.
  function getPositionAmounts(
    address posm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    (uint256 principal0, uint256 principal1, uint256 fees0, uint256 fees1) = _positionAmountsSplit(posm, tokenId);
    amount0 = principal0 + fees0;
    amount1 = principal1 + fees1;
  }

  /// @inheritdoc ISharedStrategy
  function getPositionTokens(
    address posm,
    uint256 tokenId
  ) external view override returns (address token0, address token1) {
    (PoolKey memory poolKey, ) = IPositionManager(posm).getPoolAndPositionInfo(tokenId);
    token0 = Currency.unwrap(poolKey.currency0);
    token1 = Currency.unwrap(poolKey.currency1);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionPrincipalAmounts(
    address posm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    (amount0, amount1, , ) = _positionAmountsSplit(posm, tokenId);
  }

  /// @dev See ISharedStrategy.getPositionPrincipalAmounts. V4 splits principal (from liquidity at
  ///      current sqrtPrice) and uncollected fees (from fee-growth deltas) via the same StateLibrary
  ///      pattern as `getPositionAmounts`, just returned separately so the vault can pick the correct
  ///      one for top-ups vs valuation.
  function _positionAmountsSplit(
    address posm,
    uint256 tokenId
  ) private view returns (uint256 principal0, uint256 principal1, uint256 fees0, uint256 fees1) {
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, PositionInfo positionInfo) = pm.getPoolAndPositionInfo(tokenId);
    uint128 liquidity = pm.getPositionLiquidity(tokenId);
    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();

    IPoolManager manager = pm.poolManager();
    PoolId poolId = poolKey.toId();
    (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolId);

    if (liquidity > 0) {
      (principal0, principal1) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtPriceX96,
        TickMath.getSqrtPriceAtTick(tickLower),
        TickMath.getSqrtPriceAtTick(tickUpper),
        liquidity
      );
    }

    (fees0, fees1) = _uncollectedFees(pm, manager, poolId, tickLower, tickUpper, tokenId);
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

  function _posmNftOwnedByVault(address posm, uint256 id) private view returns (bool) {
    try IERC721(posm).ownerOf(id) returns (address owner) {
      return owner == address(this);
    } catch {
      return false;
    }
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  function _requireWhitelistedPosm(address posm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), posm);
  }

  /// @notice Validates calldata passed to `IV4UtilsRouter.execute` for swap-router safety.
  /// @dev **Scope:**
  /// - Only calldata whose first 4 bytes equal `IV4Utils.execute(address,uint256,(uint8,bytes))` is decoded.
  ///   Any other selector returns without further validation; those flows still run only when `posm` is
  ///   whitelisted and the strategy is a whitelisted vault target.
  /// - For `DECREASE_AND_SWAP`, the embedded `swapParams` array must be empty. Full whitelist validation of
  ///   each `swapParams[i].swapData` router is not feasible (swap calldata format is opaque at this layer).
  ///   Operators requiring a swap after a decrease must use a separate CALL action, which validates against
  ///   `configManager.isWhitelistedSwapRouter`.
  /// - `ADJUST_RANGE` and `COMPOUND` do not encode third-party swap routers so no further check is needed.
  /// - Silent early returns are normal: most `params` blobs are not `execute` calls at all.
  function _validateV4ExecuteCalldataSwapRouters(bytes memory params, address posm, uint256 tokenId) private pure {
    if (params.length < 4) return;
    if (bytes4(params) != IV4Utils.execute.selector) return;
    bytes memory body = new bytes(params.length - 4);
    for (uint256 j; j < body.length; ) {
      body[j] = params[j + 4];
      unchecked {
        ++j;
      }
    }
    (address p, uint256 tid, IV4Utils.Instructions memory instr) = abi.decode(
      body,
      (address, uint256, IV4Utils.Instructions)
    );
    require(p == posm && tid == tokenId, ISharedCommon.InvalidOperation());

    if (instr.action == IV4Utils.UtilActions.DECREASE_AND_SWAP) {
      IV4Utils.DecreaseAndSwapParams memory decParams = abi.decode(instr.params, (IV4Utils.DecreaseAndSwapParams));
      // Reject non-zero swapParams: swap router addresses are embedded inside swapData and cannot
      // be decoded and validated against the whitelist without knowing the external router's ABI.
      // Use a separate CALL action for any swap so it goes through isWhitelistedSwapRouter.
      require(decParams.swapParams.length == 0, ISharedCommon.InvalidSwapRouter(address(0)));
    }
  }

  function _platformFeeX64FromConfig(ISharedConfigManager cm) private view returns (uint64) {
    uint16 bps = cm.platformFeeBasisPoint();
    if (bps == 0) return 0;
    require(bps <= 10_000, ISharedCommon.InvalidFeeBasisPoint());
    return uint64(FullMath.mulDiv(uint256(bps), _FEE_Q64, 10_000));
  }

  function _vaultOwnerFeeX64(uint16 basisPoints) private pure returns (uint64) {
    if (basisPoints == 0) return 0;
    return uint64(FullMath.mulDiv(uint256(basisPoints), _FEE_Q64, 10_000));
  }
}
