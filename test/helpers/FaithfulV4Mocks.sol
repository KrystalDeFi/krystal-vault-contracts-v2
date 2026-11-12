// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Pool } from "@uniswap/v4-core/src/libraries/Pool.sol";
import { Position as V4Position } from "@uniswap/v4-core/src/libraries/Position.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { FullMath as V4FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { FixedPoint128 as V4FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { SafeCast as V4SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { SlippageCheck } from "@uniswap/v4-periphery/src/libraries/SlippageCheck.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { ActionConstants } from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";

import { FaithfulPermit2 } from "./FaithfulTokens.sol";

// Faithful mocks of Uniswap V4's PoolManager (v4-core) and PositionManager (v4-periphery) for the paths the shared
// strategies drive. Pool state transitions are v4-core's own `Pool` library (Pool.modifyLiquidity / donate /
// getFeeGrowthInside), stored at StateLibrary's slot layout so the strategies' extsload reads see real state.
//
// Reproduced upstream behaviour:
//   - every modifyLiquidity credits the position's accrued fees to the caller: INCREASE / DECREASE (including a
//     zero-liquidity one) realise fees, and CLOSE_CURRENCY / TAKE_PAIR net them against principal;
//   - slippage is checked on principal only (`liquidityDelta - feesAccrued`, SlippageCheck.validateMaxIn/MinOut);
//   - debts settle by pulling from the locker through Permit2 (sync -> transferFrom -> settle), credits are taken
//     out of the manager, and the unlock reverts CurrencyNotSettled while any delta is open;
//   - increase / decrease require the locker to own or be approved for the NFT.
// Not modelled: native currency (pools are ERC-20 only and modifyLiquidities rejects msg.value), hooks (address(0)
// only), swaps / price moves (fees are credited with Pool.donate, as a swap's LP fee would be), protocol fees,
// subscribers, ERC-6909 claims.

/// @dev v4-core IUnlockCallback.
interface IFaithfulUnlockCallback {
  function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract FaithfulV4PoolManager {
  using SafeERC20 for IERC20;
  using Pool for Pool.State;
  using PoolIdLibrary for PoolKey;
  using V4SafeCast for uint256;
  using V4SafeCast for int256;
  using V4Position for mapping(bytes32 => V4Position.State);

  error ManagerLocked();
  error AlreadyUnlocked();
  error CurrencyNotSettled();
  error UnsupportedPoolKey();

  /// @dev PoolManager's inherited storage (Owned, ProtocolFees, ERC6909) fills slots 0-5, which puts `_pools` at
  ///      StateLibrary.POOLS_SLOT (6): StateLibrary's extsload reads land on this mapping.
  uint256[6] private __inheritedSlots;
  mapping(PoolId id => Pool.State) internal _pools;

  // Transient storage upstream (Lock, NonzeroDeltaCount, CurrencyDelta, CurrencyReserves); a mock unlock never
  // spans transactions, so plain storage behaves the same.
  bool internal _unlocked;
  uint256 internal _nonzeroDeltaCount;
  mapping(address target => mapping(Currency currency => int256)) internal _deltas;
  Currency internal _syncedCurrency;
  uint256 internal _syncedReserves;

  modifier onlyWhenUnlocked() {
    if (!_unlocked) revert ManagerLocked();
    _;
  }

  /// @dev PoolManager.initialize for hookless ERC-20 pools: sorted currencies, static LP fee.
  function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
    if (
      Currency.unwrap(key.currency0) == address(0) || Currency.unwrap(key.currency0) >= Currency.unwrap(key.currency1)
        || address(key.hooks) != address(0)
    ) revert UnsupportedPoolKey();
    tick = _pools[key.toId()].initialize(sqrtPriceX96, key.fee);
  }

  /// @dev PoolManager.unlock: the callback runs with the manager unlocked; any open delta afterwards reverts.
  function unlock(bytes calldata data) external returns (bytes memory result) {
    if (_unlocked) revert AlreadyUnlocked();
    _unlocked = true;
    result = IFaithfulUnlockCallback(msg.sender).unlockCallback(data);
    if (_nonzeroDeltaCount != 0) revert CurrencyNotSettled();
    _unlocked = false;
  }

  /// @dev PoolManager.modifyLiquidity: `callerDelta = principalDelta + feesAccrued` is accounted to the caller.
  function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata)
    external
    onlyWhenUnlocked
    returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
  {
    Pool.State storage pool = _pools[key.toId()];
    pool.checkPoolInitialized();
    BalanceDelta principalDelta;
    (principalDelta, feesAccrued) = pool.modifyLiquidity(
      Pool.ModifyLiquidityParams({
        owner: msg.sender,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        liquidityDelta: params.liquidityDelta.toInt128(),
        tickSpacing: key.tickSpacing,
        salt: params.salt
      })
    );
    callerDelta = principalDelta + feesAccrued;
    _accountDelta(key.currency0, callerDelta.amount0(), msg.sender);
    _accountDelta(key.currency1, callerDelta.amount1(), msg.sender);
  }

  /// @dev PoolManager.take: sends `amount` out and debits the caller.
  function take(Currency currency, address to, uint256 amount) external onlyWhenUnlocked {
    _accountDelta(currency, -(amount.toInt128()), msg.sender);
    IERC20(Currency.unwrap(currency)).safeTransfer(to, amount);
  }

  /// @dev PoolManager.sync: snapshot reserves before a payment.
  function sync(Currency currency) external {
    _syncedCurrency = currency;
    _syncedReserves = IERC20(Currency.unwrap(currency)).balanceOf(address(this));
  }

  /// @dev PoolManager.settle (ERC-20 branch): credits the caller with what arrived since `sync`.
  function settle() external payable onlyWhenUnlocked returns (uint256 paid) {
    Currency currency = _syncedCurrency;
    if (Currency.unwrap(currency) == address(0) || msg.value != 0) revert UnsupportedPoolKey();
    paid = IERC20(Currency.unwrap(currency)).balanceOf(address(this)) - _syncedReserves;
    _syncedCurrency = Currency.wrap(address(0));
    _accountDelta(currency, paid.toInt128(), msg.sender);
  }

  /// @dev TransientStateLibrary.currencyDelta.
  function currencyDelta(address target, Currency currency) external view returns (int256) {
    return _deltas[target][currency];
  }

  /// @dev Test hook: credits LP fees the way a swap's fee does (Pool.donate: feeGrowthGlobal += amount * Q128 /
  ///      liquidity); the fee tokens are paid in by the caller.
  function accrueFees(PoolKey memory key, uint256 amount0, uint256 amount1) external {
    _pools[key.toId()].donate(amount0, amount1);
    if (amount0 > 0) IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), amount0);
    if (amount1 > 0) IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), amount1);
  }

  /// @dev Test oracle from the pool's own ledger: the feesOwed Position.update would credit to this position on its
  ///      next modifyLiquidity (wrapping fee-growth delta times liquidity over Q128).
  function pendingFees(PoolKey memory key, address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
    external
    view
    returns (uint256 fees0, uint256 fees1)
  {
    Pool.State storage pool = _pools[key.toId()];
    (uint256 inside0, uint256 inside1) = pool.getFeeGrowthInside(tickLower, tickUpper);
    V4Position.State storage position = pool.positions.get(owner, tickLower, tickUpper, salt);
    unchecked {
      fees0 = V4FullMath.mulDiv(inside0 - position.feeGrowthInside0LastX128, position.liquidity, V4FixedPoint128.Q128);
      fees1 = V4FullMath.mulDiv(inside1 - position.feeGrowthInside1LastX128, position.liquidity, V4FixedPoint128.Q128);
    }
  }

  /// @dev Extsload: raw storage reads, as StateLibrary expects.
  function extsload(bytes32 slot) external view returns (bytes32 value) {
    assembly ("memory-safe") {
      value := sload(slot)
    }
  }

  function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
    values = new bytes32[](nSlots);
    for (uint256 i; i < nSlots; ++i) {
      bytes32 slot = bytes32(uint256(startSlot) + i);
      bytes32 value;
      assembly ("memory-safe") {
        value := sload(slot)
      }
      values[i] = value;
    }
  }

  function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values) {
    values = new bytes32[](slots.length);
    for (uint256 i; i < slots.length; ++i) {
      bytes32 slot = slots[i];
      bytes32 value;
      assembly ("memory-safe") {
        value := sload(slot)
      }
      values[i] = value;
    }
  }

  /// @dev PoolManager._accountDelta with NonzeroDeltaCount bookkeeping.
  function _accountDelta(Currency currency, int128 delta, address target) internal {
    if (delta == 0) return;
    int256 previous = _deltas[target][currency];
    int256 next = previous + delta;
    if (next == 0) _nonzeroDeltaCount--;
    else if (previous == 0) _nonzeroDeltaCount++;
    _deltas[target][currency] = next;
  }
}

/// @dev v4-periphery PositionManager for INCREASE_LIQUIDITY, DECREASE_LIQUIDITY, MINT_POSITION, SETTLE_PAIR,
///      TAKE_PAIR, CLOSE_CURRENCY and SWEEP. Positions are keyed by (this, range, salt = tokenId) in the pool.
contract FaithfulV4PositionManager is ERC721, IFaithfulUnlockCallback {
  using SafeERC20 for IERC20;
  using SlippageCheck for BalanceDelta;
  using PoolIdLibrary for PoolKey;
  using PositionInfoLibrary for PositionInfo;
  using StateLibrary for IPoolManager;
  using V4SafeCast for uint256;

  error NotApproved(address caller);
  error DeadlinePassed(uint256 deadline);
  error UnsupportedAction(uint256 action);
  error DeltaNotPositive(Currency currency);
  error DeltaNotNegative(Currency currency);
  error InputLengthMismatch();
  error ContractLocked();
  error NativeValueUnsupported();

  FaithfulV4PoolManager internal immutable _manager;
  FaithfulPermit2 public immutable permit2;
  uint256 public nextTokenId = 1;
  mapping(uint256 tokenId => PositionInfo info) public positionInfo;
  mapping(bytes25 poolId => PoolKey poolKey) public poolKeys;
  address internal _locker;

  constructor(FaithfulV4PoolManager manager_, FaithfulPermit2 permit2_)
    ERC721("Uniswap v4 Positions NFT", "UNI-V4-POSM")
  {
    _manager = manager_;
    permit2 = permit2_;
  }

  function poolManager() external view returns (IPoolManager) {
    return IPoolManager(address(_manager));
  }

  /// @dev PositionManager.modifyLiquidities: deadline check, reentrancy lock, the locker is `msgSender()`.
  function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable {
    if (block.timestamp > deadline) revert DeadlinePassed(deadline);
    if (_locker != address(0)) revert ContractLocked();
    if (msg.value != 0) revert NativeValueUnsupported();
    _locker = msg.sender;
    _manager.unlock(unlockData);
    _locker = address(0);
  }

  /// @dev BaseActionsRouter._executeActionsWithoutUnlock.
  function unlockCallback(bytes calldata data) external returns (bytes memory) {
    require(msg.sender == address(_manager), "callback");
    (bytes memory actions, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));
    if (actions.length != params.length) revert InputLengthMismatch();
    for (uint256 i; i < actions.length; ++i) {
      _handleAction(uint8(actions[i]), params[i]);
    }
    return "";
  }

  function getPoolAndPositionInfo(uint256 tokenId) public view returns (PoolKey memory poolKey, PositionInfo info) {
    info = positionInfo[tokenId];
    poolKey = poolKeys[info.poolId()];
  }

  /// @dev PositionManager.getPositionLiquidity, read through StateLibrary like upstream.
  function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity) {
    (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);
    bytes32 positionId =
      V4Position.calculatePositionKey(address(this), info.tickLower(), info.tickUpper(), bytes32(tokenId));
    liquidity = IPoolManager(address(_manager)).getPositionLiquidity(poolKey.toId(), positionId);
  }

  /// @dev Test oracle: fees the pool will credit this NFT on its next modifyLiquidity.
  function pendingFees(uint256 tokenId) external view returns (uint256, uint256) {
    (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);
    return _manager.pendingFees(poolKey, address(this), info.tickLower(), info.tickUpper(), bytes32(tokenId));
  }

  /// @dev PositionManager._handleAction for the supported actions.
  function _handleAction(uint256 action, bytes memory params) internal {
    if (action == Actions.INCREASE_LIQUIDITY) {
      (uint256 tokenId, uint256 liquidity, uint128 amount0Max, uint128 amount1Max, bytes memory hookData) =
        abi.decode(params, (uint256, uint256, uint128, uint128, bytes));
      _modify(tokenId, liquidity.toInt256(), hookData).validateMaxIn(amount0Max, amount1Max);
    } else if (action == Actions.DECREASE_LIQUIDITY) {
      (uint256 tokenId, uint256 liquidity, uint128 amount0Min, uint128 amount1Min, bytes memory hookData) =
        abi.decode(params, (uint256, uint256, uint128, uint128, bytes));
      _modify(tokenId, -(liquidity.toInt256()), hookData).validateMinOut(amount0Min, amount1Min);
    } else if (action == Actions.MINT_POSITION) {
      (
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner,
        bytes memory hookData
      ) = abi.decode(params, (PoolKey, int24, int24, uint256, uint128, uint128, address, bytes));
      _mintPosition(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, _mapRecipient(owner), hookData);
    } else if (action == Actions.SETTLE_PAIR) {
      (Currency currency0, Currency currency1) = abi.decode(params, (Currency, Currency));
      _settle(currency0, _locker, _getFullDebt(currency0));
      _settle(currency1, _locker, _getFullDebt(currency1));
    } else if (action == Actions.TAKE_PAIR) {
      (Currency currency0, Currency currency1, address recipient) = abi.decode(params, (Currency, Currency, address));
      address to = _mapRecipient(recipient);
      _take(currency0, to, _getFullCredit(currency0));
      _take(currency1, to, _getFullCredit(currency1));
    } else if (action == Actions.CLOSE_CURRENCY) {
      Currency currency = abi.decode(params, (Currency));
      int256 delta = _manager.currencyDelta(address(this), currency);
      if (delta < 0) _settle(currency, _locker, uint256(-delta));
      else _take(currency, _locker, uint256(delta));
    } else if (action == Actions.SWEEP) {
      // PositionManager._sweep (ERC-20 currencies only in this mock).
      (Currency currency, address to) = abi.decode(params, (Currency, address));
      if (Currency.unwrap(currency) == address(0)) revert NativeValueUnsupported();
      uint256 balance = IERC20(Currency.unwrap(currency)).balanceOf(address(this));
      if (balance > 0) IERC20(Currency.unwrap(currency)).safeTransfer(_mapRecipient(to), balance);
    } else {
      revert UnsupportedAction(action);
    }
  }

  /// @dev PositionManager._increase / _decrease: `onlyIfApproved(msgSender(), tokenId)`, then modifyLiquidity with
  ///      salt = tokenId. Returns the principal-only delta the slippage check is applied to.
  function _modify(uint256 tokenId, int256 liquidityChange, bytes memory hookData)
    internal
    returns (BalanceDelta principalDelta)
  {
    if (!_isAuthorized(_ownerOf(tokenId), _locker, tokenId)) revert NotApproved(_locker);
    (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);
    (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) = _manager.modifyLiquidity(
      poolKey,
      ModifyLiquidityParams({
        tickLower: info.tickLower(),
        tickUpper: info.tickUpper(),
        liquidityDelta: liquidityChange,
        salt: bytes32(tokenId)
      }),
      hookData
    );
    principalDelta = liquidityDelta - feesAccrued;
  }

  /// @dev PositionManager._mint: next id, position info, first-seen pool key, then the principal max-in check.
  function _mintPosition(
    PoolKey memory poolKey,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity,
    uint128 amount0Max,
    uint128 amount1Max,
    address owner,
    bytes memory hookData
  ) internal {
    uint256 tokenId = nextTokenId++;
    _mint(owner, tokenId);
    PositionInfo info = PositionInfoLibrary.initialize(poolKey, tickLower, tickUpper);
    positionInfo[tokenId] = info;
    bytes25 poolId = info.poolId();
    if (poolKeys[poolId].tickSpacing == 0) poolKeys[poolId] = poolKey;
    (BalanceDelta liquidityDelta,) = _manager.modifyLiquidity(
      poolKey,
      ModifyLiquidityParams({
        tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidity.toInt256(), salt: bytes32(tokenId)
      }),
      hookData
    );
    liquidityDelta.validateMaxIn(amount0Max, amount1Max);
  }

  /// @dev DeltaResolver._settle + PositionManager._pay: sync, Permit2 pull from the payer, settle.
  function _settle(Currency currency, address payer, uint256 amount) internal {
    if (amount == 0) return;
    _manager.sync(currency);
    permit2.transferFrom(payer, address(_manager), uint160(amount), Currency.unwrap(currency));
    _manager.settle();
  }

  /// @dev DeltaResolver._take.
  function _take(Currency currency, address recipient, uint256 amount) internal {
    if (amount == 0) return;
    _manager.take(currency, recipient, amount);
  }

  function _getFullDebt(Currency currency) internal view returns (uint256) {
    int256 delta = _manager.currencyDelta(address(this), currency);
    if (delta > 0) revert DeltaNotNegative(currency);
    return uint256(-delta);
  }

  function _getFullCredit(Currency currency) internal view returns (uint256) {
    int256 delta = _manager.currencyDelta(address(this), currency);
    if (delta < 0) revert DeltaNotPositive(currency);
    return uint256(delta);
  }

  /// @dev BaseActionsRouter._mapRecipient.
  function _mapRecipient(address recipient) internal view returns (address) {
    if (recipient == ActionConstants.MSG_SENDER) return _locker;
    if (recipient == ActionConstants.ADDRESS_THIS) return address(this);
    return recipient;
  }
}
