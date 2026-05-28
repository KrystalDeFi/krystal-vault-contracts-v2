// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

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
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
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
import { IFeeTaker } from "../../public-vault/interfaces/strategies/IFeeTaker.sol";
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

  struct MintParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 minLiquidity;
    bytes hookData;
    uint256 deadline;
  }

  struct IncreaseLiquidityParams {
    uint256 minLiquidity;
    bytes hookData;
    uint256 deadline;
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

  struct AdjustRangeParams {
    bytes collectFeesHookData;
    SwapParams[] swapParams;
    MintParams mintParams;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
    bool compoundFees;
  }

  struct CompoundFeesParams {
    bytes collectFeesHookData;
    SwapParams[] swapParams;
    IncreaseLiquidityParams increaseParams;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  function execute(address posm, uint256 tokenId, Instructions calldata instructions) external;
}

/// @title SharedV4Strategy
/// @notice Uniswap V4 LP operations for SharedVault with token validation and position tracking
contract SharedV4Strategy is ISharedStrategy, IFeeTaker {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;
  using PoolIdLibrary for PoolKey;
  using PositionInfoLibrary for PositionInfo;
  using SafeCast for uint256;
  using StateLibrary for IPoolManager;

  uint256 private constant Q64 = 0x10000000000000000;

  address public immutable swapRouter;

  enum OperationType {
    EXECUTE,
    SAFE_TRANSFER_NFT
  }

  constructor(address _swapRouter) {
    require(_swapRouter != address(0), ISharedCommon.ZeroAddress());
    swapRouter = _swapRouter;
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
    require(approveTokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    IV4Utils.Instructions memory instructions = _decodeV4ExecuteCalldata(params, posm, tokenId);
    _validateApprovalList(approveTokens, approveAmounts);
    require(ethValue == 0, ISharedCommon.InvalidAmount());

    IPositionManager pm = IPositionManager(posm);

    // Snapshot next tokenId before the call to detect newly minted positions
    uint256 nextIdBefore = pm.nextTokenId();

    _executeInstruction(posm, tokenId, instructions);

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
      // Partial decrease, compound, or increase — must NOT have minted a new vault-owned NFT
      require(pm.nextTokenId() == nextIdBefore || !_posmNftOwnedByVault(posm, nextIdBefore), InvalidPoolTokens());
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

    IV4Utils.Instructions memory instructions = abi.decode(instruction, (IV4Utils.Instructions));
    _executeInstruction(posm, tokenId, instructions);

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
      // Partial or non-exit operation — must NOT have minted a new vault-owned NFT
      require(pm.nextTokenId() == nextIdBefore || !_posmNftOwnedByVault(posm, nextIdBefore), InvalidPoolTokens());
      changes = new PositionChange[](0);
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Uses `INCREASE_LIQUIDITY` + `CLOSE_CURRENCY` so the PositionManager pulls the exact
  ///      amounts required for the computed liquidity through Permit2. Any amount not needed for
  ///      the current pool/range ratio stays idle in the vault. Permit2 approval is set inline.
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

    (uint160 sqrtPriceX96, , , ) = pm.poolManager().getSlot0(poolKey.toId());
    int24 tickLower = positionInfo.tickLower();
    int24 tickUpper = positionInfo.tickUpper();
    uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtPriceAtTick(tickLower),
      TickMath.getSqrtPriceAtTick(tickUpper),
      amount0,
      amount1
    );
    if (liquidityToAdd == 0) return;

    // Capture pre-deposit state for slippage check (only when slippage protection requested)
    uint128 liquidityBefore;
    if (slippageBps > 0) liquidityBefore = pm.getPositionLiquidity(tokenId);

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

    // INCREASE_LIQUIDITY (0x00) + CLOSE_CURRENCY (0x12) for each token
    bytes memory actions = abi.encodePacked(uint8(0x00), uint8(0x12), uint8(0x12));
    bytes[] memory params = new bytes[](3);
    params[0] = abi.encode(tokenId, uint256(liquidityToAdd), uint128(amount0), uint128(amount1), bytes(""));
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
      uint128 minLiquidity = uint128(FullMath.mulDiv(liquidityToAdd, 10_000 - slippageBps, 10_000));
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
  function collectFees(address posm, uint256 tokenId, uint16 /* vaultOwnerFeeBasisPoint */ ) external override {
    _collectFees(posm, tokenId, SharedStrategyFeeConfig.performanceFeeConfig());
  }

  function _collectFees(address posm, uint256 tokenId, ICommon.FeeConfig memory fc) private {
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

    _applyFees(token0, collected0, token1, collected1, fc);
  }

  /// @dev V3/Aerodrome route fees through `LpFeeTaker.takeFees`, which encapsulates approval + split.
  ///      V4 reimplements the split inline because V4Utils integration with LpFeeTaker does not exist:
  ///      the V4 PositionManager uses Permit2 approvals and its own settlement flow, making the
  ///      LpFeeTaker approval-then-call pattern incompatible. Any future fee-policy change must be
  ///      applied here in addition to LpFeeTaker.
  function _applyFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    ICommon.FeeConfig memory fc
  ) private returns (uint256 feeTaken0, uint256 feeTaken1) {
    if (fc.platformFeeBasisPoint > 0 && fc.platformFeeRecipient != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.platformFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.platformFeeBasisPoint, 10_000);
      if (fee0 > 0) {
        IERC20(token0).safeTransfer(fc.platformFeeRecipient, fee0);
        emit FeeCollected(address(this), FeeType.PLATFORM, fc.platformFeeRecipient, token0, fee0);
        feeTaken0 += fee0;
      }
      if (fee1 > 0) {
        IERC20(token1).safeTransfer(fc.platformFeeRecipient, fee1);
        emit FeeCollected(address(this), FeeType.PLATFORM, fc.platformFeeRecipient, token1, fee1);
        feeTaken1 += fee1;
      }
    }
    if (fc.vaultOwnerFeeBasisPoint > 0 && fc.vaultOwner != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.vaultOwnerFeeBasisPoint, 10_000);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.vaultOwnerFeeBasisPoint, 10_000);
      if (fee0 > 0) {
        IERC20(token0).safeTransfer(fc.vaultOwner, fee0);
        emit FeeCollected(address(this), FeeType.OWNER, fc.vaultOwner, token0, fee0);
        feeTaken0 += fee0;
      }
      if (fee1 > 0) {
        IERC20(token1).safeTransfer(fc.vaultOwner, fee1);
        emit FeeCollected(address(this), FeeType.OWNER, fc.vaultOwner, token1, fee1);
        feeTaken1 += fee1;
      }
    }
    if (fc.gasFeeX64 > 0 && fc.gasFeeRecipient != address(0)) {
      uint256 fee0 = FullMath.mulDiv(amount0, fc.gasFeeX64, Q64);
      uint256 fee1 = FullMath.mulDiv(amount1, fc.gasFeeX64, Q64);
      if (fee0 > 0) {
        IERC20(token0).safeTransfer(fc.gasFeeRecipient, fee0);
        emit FeeCollected(address(this), FeeType.GAS, fc.gasFeeRecipient, token0, fee0);
        feeTaken0 += fee0;
      }
      if (fee1 > 0) {
        IERC20(token1).safeTransfer(fc.gasFeeRecipient, fee1);
        emit FeeCollected(address(this), FeeType.GAS, fc.gasFeeRecipient, token1, fee1);
        feeTaken1 += fee1;
      }
    }
  }

  function _executeInstruction(address posm, uint256 tokenId, IV4Utils.Instructions memory instructions) private {
    IPositionManager pm = IPositionManager(posm);
    (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    _validateVaultToken(token0);
    _validateVaultToken(token1);

    if (instructions.action == IV4Utils.UtilActions.COMPOUND) {
      IV4Utils.CompoundFeesParams memory compoundParams = abi.decode(
        instructions.params,
        (IV4Utils.CompoundFeesParams)
      );
      (uint256 amount0, uint256 amount1) = _collectV4GeneratedFees(
        posm,
        tokenId,
        poolKey,
        compoundParams.collectFeesHookData,
        compoundParams.gasFeeX64
      );
      (amount0, amount1) = _executeV4Swaps(token0, token1, amount0, amount1, compoundParams.swapParams);
      _increaseV4WithAmounts(posm, tokenId, poolKey, amount0, amount1, compoundParams.increaseParams);
    } else if (instructions.action == IV4Utils.UtilActions.DECREASE_AND_SWAP) {
      IV4Utils.DecreaseAndSwapParams memory decParams = abi.decode(
        instructions.params,
        (IV4Utils.DecreaseAndSwapParams)
      );
      (uint256 amount0, uint256 amount1) = _collectV4GeneratedFees(
        posm,
        tokenId,
        poolKey,
        decParams.decreaseParams.hookData,
        decParams.gasFeeX64
      );
      (uint256 principal0, uint256 principal1) = _decreaseV4Principal(
        posm,
        poolKey,
        tokenId,
        decParams.decreaseParams.liquidity,
        decParams.decreaseParams.amount0Min,
        decParams.decreaseParams.amount1Min,
        decParams.decreaseParams.hookData,
        decParams.gasFeeX64,
        decParams.decreaseParams.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      _executeV4Swaps(token0, token1, amount0, amount1, decParams.swapParams);
    } else if (instructions.action == IV4Utils.UtilActions.ADJUST_RANGE) {
      IV4Utils.AdjustRangeParams memory adjustParams = abi.decode(
        instructions.params,
        (IV4Utils.AdjustRangeParams)
      );
      (uint256 amount0, uint256 amount1) = _collectV4GeneratedFees(
        posm,
        tokenId,
        poolKey,
        adjustParams.collectFeesHookData,
        adjustParams.gasFeeX64
      );
      uint128 liquidity = pm.getPositionLiquidity(tokenId);
      (uint256 principal0, uint256 principal1) = _decreaseV4Principal(
        posm,
        poolKey,
        tokenId,
        liquidity,
        0,
        0,
        "",
        adjustParams.gasFeeX64,
        adjustParams.mintParams.deadline
      );
      amount0 += principal0;
      amount1 += principal1;
      (amount0, amount1) = _executeV4Swaps(token0, token1, amount0, amount1, adjustParams.swapParams);
      _mintV4WithAmounts(posm, poolKey, amount0, amount1, adjustParams.mintParams);
    } else {
      revert ISharedCommon.InvalidOperation();
    }
  }

  function _collectV4GeneratedFees(
    address posm,
    uint256 tokenId,
    PoolKey memory poolKey,
    bytes memory hookData,
    uint64 gasFeeX64
  ) private returns (uint256 net0, uint256 net1) {
    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(
      uint8(Actions.DECREASE_LIQUIDITY),
      uint8(Actions.CLOSE_CURRENCY),
      uint8(Actions.CLOSE_CURRENCY)
    );
    bytes[] memory collectParams = new bytes[](3);
    collectParams[0] = abi.encode(tokenId, uint128(0), uint256(0), uint256(0), hookData);
    collectParams[1] = abi.encode(poolKey.currency0);
    collectParams[2] = abi.encode(poolKey.currency1);
    IPositionManager(posm).modifyLiquidities(abi.encode(actions, collectParams), block.timestamp);

    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (collected0 == 0 && collected1 == 0) return (0, 0);

    ICommon.FeeConfig memory fc = SharedStrategyFeeConfig.performanceFeeConfig();
    if (gasFeeX64 > 0) {
      fc.gasFeeX64 = gasFeeX64;
      fc.gasFeeRecipient = msg.sender;
    }
    (uint256 fee0, uint256 fee1) = _applyFees(token0, collected0, token1, collected1, fc);
    net0 = collected0 - fee0;
    net1 = collected1 - fee1;
  }

  function _decreaseV4Principal(
    address posm,
    PoolKey memory poolKey,
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    bytes memory hookData,
    uint64 gasFeeX64,
    uint256 deadline
  ) private returns (uint256 net0, uint256 net1) {
    if (liquidity == 0) return (0, 0);
    IPositionManager pm = IPositionManager(posm);
    uint128 posLiquidity = pm.getPositionLiquidity(tokenId);
    if (liquidity > posLiquidity) liquidity = posLiquidity;

    address token0 = Currency.unwrap(poolKey.currency0);
    address token1 = Currency.unwrap(poolKey.currency1);
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));

    bytes memory actions = abi.encodePacked(
      uint8(Actions.DECREASE_LIQUIDITY),
      uint8(Actions.CLOSE_CURRENCY),
      uint8(Actions.CLOSE_CURRENCY)
    );
    bytes[] memory params = new bytes[](3);
    params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
    params[1] = abi.encode(poolKey.currency0);
    params[2] = abi.encode(poolKey.currency1);
    pm.modifyLiquidities(abi.encode(actions, params), deadline == 0 ? block.timestamp : deadline);

    uint256 principal0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 principal1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (gasFeeX64 == 0 || (principal0 == 0 && principal1 == 0)) return (principal0, principal1);

    ICommon.FeeConfig memory gasOnly = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: msg.sender
    });
    (uint256 fee0, uint256 fee1) = _applyFees(token0, principal0, token1, principal1, gasOnly);
    net0 = principal0 - fee0;
    net1 = principal1 - fee1;
  }

  function _increaseV4WithAmounts(
    address posm,
    uint256 tokenId,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    IV4Utils.IncreaseLiquidityParams memory params
  ) private {
    if (amount0 == 0 && amount1 == 0) return;
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    IPositionManager pm = IPositionManager(posm);
    PositionInfo positionInfo = pm.positionInfo(tokenId);
    (uint160 sqrtPriceX96, , , ) = pm.poolManager().getSlot0(poolKey.toId());
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtPriceAtTick(positionInfo.tickLower()),
      TickMath.getSqrtPriceAtTick(positionInfo.tickUpper()),
      amount0,
      amount1
    );
    require(liquidity >= params.minLiquidity, ISharedCommon.InsufficientOutput());
    if (liquidity == 0) return;

    _approveV4PositionManager(posm, poolKey, amount0, amount1);
    bytes memory actions = abi.encodePacked(
      uint8(Actions.INCREASE_LIQUIDITY),
      uint8(Actions.CLOSE_CURRENCY),
      uint8(Actions.CLOSE_CURRENCY)
    );
    bytes[] memory callParams = new bytes[](3);
    callParams[0] = abi.encode(tokenId, uint256(liquidity), uint128(amount0), uint128(amount1), params.hookData);
    callParams[1] = abi.encode(poolKey.currency0);
    callParams[2] = abi.encode(poolKey.currency1);
    pm.modifyLiquidities(abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _mintV4WithAmounts(
    address posm,
    PoolKey memory poolKey,
    uint256 amount0,
    uint256 amount1,
    IV4Utils.MintParams memory params
  ) private returns (uint256 tokenId) {
    if (amount0 == 0 && amount1 == 0) revert ISharedCommon.InvalidAmount();
    require(amount0 <= type(uint128).max && amount1 <= type(uint128).max, ISharedCommon.InvalidAmount());
    IPositionManager pm = IPositionManager(posm);
    (uint160 sqrtPriceX96, , , ) = pm.poolManager().getSlot0(poolKey.toId());
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtPriceAtTick(params.tickLower),
      TickMath.getSqrtPriceAtTick(params.tickUpper),
      amount0,
      amount1
    );
    require(liquidity >= params.minLiquidity && liquidity > 0, ISharedCommon.InsufficientOutput());

    tokenId = pm.nextTokenId();
    _approveV4PositionManager(posm, poolKey, amount0, amount1);
    bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
    bytes[] memory callParams = new bytes[](2);
    callParams[0] = abi.encode(
      poolKey,
      params.tickLower,
      params.tickUpper,
      liquidity,
      uint128(amount0),
      uint128(amount1),
      address(this),
      params.hookData
    );
    callParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
    pm.modifyLiquidities(abi.encode(actions, callParams), params.deadline == 0 ? block.timestamp : params.deadline);
    _clearV4PositionManagerApprovals(posm, poolKey, amount0, amount1);
  }

  function _executeV4Swaps(
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    IV4Utils.SwapParams[] memory swapParams
  ) private returns (uint256 total0, uint256 total1) {
    total0 = amount0;
    total1 = amount1;
    for (uint256 i; i < swapParams.length; ) {
      IV4Utils.SwapParams memory swapParam = swapParams[i];
      require(
        _isV4SwapInputAllowed(token0, token1, swapParam.tokenIn, swapParams, i) &&
          _isV4SwapOutputAllowed(token0, token1, swapParam.tokenOut, swapParams, i),
        InvalidPoolTokens()
      );

      uint256 amountIn = swapParam.amountIn;
      if (swapParam.tokenIn == token0) {
        if (amountIn == 0) amountIn = total0;
        require(amountIn <= total0, ISharedCommon.InvalidAmount());
      } else if (swapParam.tokenIn == token1) {
        if (amountIn == 0) amountIn = total1;
        require(amountIn <= total1, ISharedCommon.InvalidAmount());
      } else {
        uint256 balance = IERC20(swapParam.tokenIn).balanceOf(address(this));
        if (amountIn == 0) amountIn = balance;
        require(amountIn <= balance, ISharedCommon.InvalidAmount());
      }

      if (amountIn == 0) {
        require(swapParam.amountOutMin == 0, ISharedCommon.InsufficientOutput());
        unchecked {
          i++;
        }
        continue;
      }

      (uint256 amountInDelta, uint256 amountOutDelta) = _swapV4(
        swapParam.tokenIn,
        swapParam.tokenOut,
        amountIn,
        swapParam.amountOutMin,
        swapParam.swapData
      );
      if (swapParam.tokenIn == token0) total0 -= amountInDelta;
      else if (swapParam.tokenIn == token1) total1 -= amountInDelta;
      if (swapParam.tokenOut == token0) total0 += amountOutDelta;
      else if (swapParam.tokenOut == token1) total1 += amountOutDelta;
      unchecked {
        i++;
      }
    }
  }

  function _isV4SwapInputAllowed(
    address token0,
    address token1,
    address tokenIn,
    IV4Utils.SwapParams[] memory swapParams,
    uint256 index
  ) private pure returns (bool) {
    if (tokenIn == token0 || tokenIn == token1) return true;
    for (uint256 i; i < index; ) {
      if (swapParams[i].tokenOut == tokenIn) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _isV4SwapOutputAllowed(
    address token0,
    address token1,
    address tokenOut,
    IV4Utils.SwapParams[] memory swapParams,
    uint256 index
  ) private pure returns (bool) {
    if (tokenOut == token0 || tokenOut == token1) return true;
    if (tokenOut == address(0)) return false;
    for (uint256 i = index + 1; i < swapParams.length; ) {
      if (swapParams[i].tokenIn == tokenOut) return true;
      unchecked {
        i++;
      }
    }
    return false;
  }

  function _swapV4(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory swapData
  ) private returns (uint256 amountInDelta, uint256 amountOutDelta) {
    if (amountIn == 0 || swapData.length == 0 || tokenOut == address(0)) return (0, 0);

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

  function _approveV4PositionManager(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1) private {
    address permit2Addr = address(Permit2Forwarder(address(IPermit2Forwarder(posm))).permit2());
    if (amount0 > 0) {
      address token0 = Currency.unwrap(poolKey.currency0);
      IERC20(token0).safeResetAndApprove(permit2Addr, amount0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, uint160(amount0), uint48(block.timestamp + 1));
    }
    if (amount1 > 0) {
      address token1 = Currency.unwrap(poolKey.currency1);
      IERC20(token1).safeResetAndApprove(permit2Addr, amount1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, uint160(amount1), uint48(block.timestamp + 1));
    }
  }

  function _clearV4PositionManagerApprovals(address posm, PoolKey memory poolKey, uint256 amount0, uint256 amount1) private {
    address permit2Addr = address(Permit2Forwarder(address(IPermit2Forwarder(posm))).permit2());
    if (amount0 > 0) {
      address token0 = Currency.unwrap(poolKey.currency0);
      IAllowanceTransfer(permit2Addr).approve(token0, posm, 0, 0);
      IERC20(token0).safeApprove(permit2Addr, 0);
    }
    if (amount1 > 0) {
      address token1 = Currency.unwrap(poolKey.currency1);
      IAllowanceTransfer(permit2Addr).approve(token1, posm, 0, 0);
      IERC20(token1).safeApprove(permit2Addr, 0);
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Withdraw exits collect generated LP fees through collectFees() before the vault's idle snapshot.
  ///      This function only decreases principal natively and never charges platform/owner fees on principal.
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
      (PoolKey memory zeroLiquidityKey, ) = pm.getPoolAndPositionInfo(tokenId);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(
        false,
        posm,
        tokenId,
        Currency.unwrap(zeroLiquidityKey.currency0),
        Currency.unwrap(zeroLiquidityKey.currency1)
      );
      return changes;
    }

    uint128 liquidityToRemove = uint128(FullMath.mulDiv(posLiquidity, shares, totalShares));
    if (liquidityToRemove == 0) return new PositionChange[](0);

    bool isFullExit = liquidityToRemove >= posLiquidity;

    (PoolKey memory poolKey, ) = pm.getPoolAndPositionInfo(tokenId);
    _decreaseV4Principal(
      posm,
      poolKey,
      tokenId,
      liquidityToRemove,
      minAmount0,
      minAmount1,
      "",
      0,
      block.timestamp
    );

    if (isFullExit) {
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
    // Use try/catch: getPoolAndPositionInfo reverts for nonexistent tokenIds on some POSM implementations.
    // Mirrors the try/catch pattern in SharedV3Strategy._positionAmountsSplit so _verifyPositionExit's
    // staticcall to getPositionAmounts gets amtsOk=true and (0,0) for burned/invalid positions.
    PoolKey memory poolKey;
    PositionInfo positionInfo;
    try pm.getPoolAndPositionInfo(tokenId) returns (PoolKey memory key, PositionInfo info) {
      poolKey = key;
      positionInfo = info;
    } catch {
      return (0, 0, 0, 0);
    }
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

  function _validateApprovalList(address[] memory approveTokens, uint256[] memory approveAmounts) private view {
    for (uint256 i; i < approveTokens.length; ) {
      if (approveAmounts[i] > 0) _validateVaultToken(approveTokens[i]);
      unchecked {
        i++;
      }
    }
  }

  /// @notice Decodes calldata compatible with `IV4Utils.execute`.
  /// @dev Fails closed: the selector MUST be `IV4Utils.execute`. Native shared-vault execution then
  ///      handles the decoded instruction without approving or calling an external V4Utils router.
  function _decodeV4ExecuteCalldata(
    bytes memory params,
    address posm,
    uint256 tokenId
  ) private pure returns (IV4Utils.Instructions memory instructions) {
    require(
      params.length >= 4 && bytes4(params) == IV4Utils.execute.selector,
      ISharedCommon.InvalidOperation()
    );
    bytes memory body = new bytes(params.length - 4);
    for (uint256 j; j < body.length; ) {
      body[j] = params[j + 4];
      unchecked {
        ++j;
      }
    }
    (address p, uint256 tid, IV4Utils.Instructions memory decodedInstructions) = abi.decode(
      body,
      (address, uint256, IV4Utils.Instructions)
    );
    require(p == posm && tid == tokenId, ISharedCommon.InvalidOperation());
    instructions = decodedInstructions;
  }

}
