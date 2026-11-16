// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { CLPool } from "infinity-core/src/pool-cl/libraries/CLPool.sol";
import { CLPosition } from "infinity-core/src/pool-cl/libraries/CLPosition.sol";
import { Tick as CLTick } from "infinity-core/src/pool-cl/libraries/Tick.sol";
import { CLPoolParametersHelper } from "infinity-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import { FullMath as CLFullMath } from "infinity-core/src/pool-cl/libraries/FullMath.sol";
import { FixedPoint128 as CLFixedPoint128 } from "infinity-core/src/pool-cl/libraries/FixedPoint128.sol";
import { SafeCast as InfinitySafeCast } from "infinity-core/src/libraries/SafeCast.sol";
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "infinity-core/src/types/PoolId.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { BalanceDelta } from "infinity-core/src/types/BalanceDelta.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";
import { SlippageCheck } from "infinity-periphery/src/libraries/SlippageCheck.sol";
import { Actions } from "infinity-periphery/src/libraries/Actions.sol";
import { ActionConstants } from "infinity-periphery/src/libraries/ActionConstants.sol";

import { FaithfulPermit2 } from "./FaithfulTokens.sol";

// Faithful mocks of PancakeSwap Infinity's Vault + CLPoolManager (infinity-core) and CLPositionManager
// (infinity-periphery) for the paths the shared strategies drive. Twin of FaithfulV4Mocks.sol. Pool state
// transitions are infinity-core's own `CLPool` library (CLPool.modifyLiquidity / donate), and the getters are the
// CLPoolManager getters the strategies read (no extsload on Infinity). The Vault (custody, lock, deltas) is merged
// into the pool manager mock.
//
// Reproduced upstream behaviour:
//   - every modifyLiquidity credits the position's accrued fees to the caller (CLPoolManager.modifyLiquidity counts
//     `delta + feeDelta` on the user): CL_INCREASE / CL_DECREASE realise fees, CLOSE_CURRENCY / TAKE_PAIR net them;
//   - slippage is checked on principal only (`liquidityDelta - feesAccrued`, SlippageCheck.validateMaxIn/MinOut);
//   - debts settle by pulling from the locker through Permit2 (vault.sync -> transferFrom -> vault.settle), credits
//     are taken out of the vault, and the lock reverts CurrencyNotSettled while any delta is open;
//   - increase / decrease require the locker to own or be approved for the NFT;
//   - `positions(tokenId)` reads the pool position (liquidity + feeGrowthInsideLast) like CLPositionManager.positions.
// Not modelled: native currency (ERC-20 pools only; modifyLiquidities rejects msg.value), hooks (none registered),
// swaps / price moves (fees are credited with CLPool.donate, as a swap's LP fee would be), protocol fees, pausing,
// subscribers.

/// @dev infinity-core ILockCallback.
interface IFaithfulLockCallback {
  function lockAcquired(bytes calldata data) external returns (bytes memory);
}

contract FaithfulCLPoolManager {
  using SafeERC20 for IERC20;
  using CLPool for CLPool.State;
  using CLPosition for mapping(bytes32 => CLPosition.Info);
  using CLTick for mapping(int24 => CLTick.Info);
  using CLPoolParametersHelper for bytes32;
  using PoolIdLibrary for PoolKey;
  using InfinitySafeCast for uint256;
  using InfinitySafeCast for int256;

  error VaultLocked();
  error AlreadyLocked();
  error CurrencyNotSettled();
  error UnsupportedPoolKey();

  mapping(PoolId id => CLPool.State) internal _pools;

  // Vault state (transient upstream: Lock, SettlementGuard, VaultReserve).
  bool internal _locked;
  uint256 internal _unsettledDeltasCount;
  mapping(address settler => mapping(Currency currency => int256)) internal _deltas;
  Currency internal _syncedCurrency;
  uint256 internal _syncedReserves;

  modifier isLocked() {
    if (!_locked) revert VaultLocked();
    _;
  }

  /// @dev CLPoolManager.initialize for hookless ERC-20 pools managed by this manager.
  function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
    if (
      Currency.unwrap(key.currency0) == address(0) || Currency.unwrap(key.currency0) >= Currency.unwrap(key.currency1)
        || address(key.hooks) != address(0) || address(key.poolManager) != address(this)
        || uint16(uint256(key.parameters)) != 0
    ) revert UnsupportedPoolKey();
    tick = _pools[key.toId()].initialize(sqrtPriceX96, 0, key.fee);
  }

  /// @dev Vault.lock: the callback runs with the vault locked for the caller; open deltas afterwards revert.
  function lock(bytes calldata data) external returns (bytes memory result) {
    if (_locked) revert AlreadyLocked();
    _locked = true;
    result = IFaithfulLockCallback(msg.sender).lockAcquired(data);
    if (_unsettledDeltasCount != 0) revert CurrencyNotSettled();
    _locked = false;
  }

  /// @dev CLPoolManager.modifyLiquidity: returns and accounts the caller delta (principal + fees) and the fees.
  function modifyLiquidity(PoolKey memory key, ICLPoolManager.ModifyLiquidityParams memory params, bytes calldata)
    external
    isLocked
    returns (BalanceDelta delta, BalanceDelta feeDelta)
  {
    CLPool.State storage pool = _pools[key.toId()];
    pool.checkPoolInitialized();
    (delta, feeDelta) = pool.modifyLiquidity(
      CLPool.ModifyLiquidityParams({
        owner: msg.sender,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        liquidityDelta: params.liquidityDelta.toInt128(),
        tickSpacing: key.parameters.getTickSpacing(),
        salt: params.salt
      })
    );
    delta = delta + feeDelta;
    _accountDelta(key.currency0, delta.amount0(), msg.sender);
    _accountDelta(key.currency1, delta.amount1(), msg.sender);
  }

  /// @dev Vault.take.
  function take(Currency currency, address to, uint256 amount) external isLocked {
    _accountDelta(currency, -(amount.toInt128()), msg.sender);
    IERC20(Currency.unwrap(currency)).safeTransfer(to, amount);
  }

  /// @dev Vault.sync.
  function sync(Currency currency) external {
    _syncedCurrency = currency;
    _syncedReserves = IERC20(Currency.unwrap(currency)).balanceOf(address(this));
  }

  /// @dev Vault.settle (ERC-20 branch).
  function settle() external payable isLocked returns (uint256 paid) {
    Currency currency = _syncedCurrency;
    if (Currency.unwrap(currency) == address(0) || msg.value != 0) revert UnsupportedPoolKey();
    paid = IERC20(Currency.unwrap(currency)).balanceOf(address(this)) - _syncedReserves;
    _syncedCurrency = Currency.wrap(address(0));
    _accountDelta(currency, paid.toInt128(), msg.sender);
  }

  /// @dev Vault.currencyDelta.
  function currencyDelta(address settler, Currency currency) external view returns (int256) {
    return _deltas[settler][currency];
  }

  // ---- CLPoolManager getters the strategies read ----

  function getSlot0(PoolId id)
    external
    view
    returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
  {
    CLPool.State storage pool = _pools[id];
    return (pool.slot0.sqrtPriceX96(), pool.slot0.tick(), pool.slot0.protocolFee(), pool.slot0.lpFee());
  }

  function getLiquidity(PoolId id) external view returns (uint128) {
    return _pools[id].liquidity;
  }

  function getPoolTickInfo(PoolId id, int24 tick) external view returns (CLTick.Info memory) {
    return _pools[id].ticks[tick];
  }

  function getFeeGrowthGlobals(PoolId id) external view returns (uint256, uint256) {
    return (_pools[id].feeGrowthGlobal0X128, _pools[id].feeGrowthGlobal1X128);
  }

  function getPosition(PoolId id, address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
    external
    view
    returns (CLPosition.Info memory)
  {
    return _pools[id].positions.get(owner, tickLower, tickUpper, salt);
  }

  /// @dev Test hook: credits LP fees the way a swap's fee does (CLPool.donate: feeGrowthGlobal += amount * Q128 /
  ///      liquidity); the fee tokens are paid in by the caller.
  function accrueFees(PoolKey memory key, uint256 amount0, uint256 amount1) external {
    _pools[key.toId()].donate(amount0, amount1);
    if (amount0 > 0) IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), amount0);
    if (amount1 > 0) IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), amount1);
  }

  /// @dev Test oracle from the pool's own ledger: the feeDelta CLPosition.update would credit this position on its
  ///      next modifyLiquidity (wrapping fee-growth delta times liquidity over Q128).
  function pendingFees(PoolKey memory key, address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
    external
    view
    returns (uint256 fees0, uint256 fees1)
  {
    CLPool.State storage pool = _pools[key.toId()];
    (uint256 inside0, uint256 inside1) = pool.ticks
      .getFeeGrowthInside(tickLower, tickUpper, pool.slot0.tick(), pool.feeGrowthGlobal0X128, pool.feeGrowthGlobal1X128);
    CLPosition.Info storage position = pool.positions.get(owner, tickLower, tickUpper, salt);
    unchecked {
      fees0 = CLFullMath.mulDiv(inside0 - position.feeGrowthInside0LastX128, position.liquidity, CLFixedPoint128.Q128);
      fees1 = CLFullMath.mulDiv(inside1 - position.feeGrowthInside1LastX128, position.liquidity, CLFixedPoint128.Q128);
    }
  }

  /// @dev Vault accounting with SettlementGuard's unsettled-delta count.
  function _accountDelta(Currency currency, int128 delta, address settler) internal {
    if (delta == 0) return;
    int256 previous = _deltas[settler][currency];
    int256 next = previous + delta;
    if (next == 0) _unsettledDeltasCount--;
    else if (previous == 0) _unsettledDeltasCount++;
    _deltas[settler][currency] = next;
  }
}

/// @dev infinity-periphery CLPositionManager for CL_INCREASE_LIQUIDITY, CL_DECREASE_LIQUIDITY, CL_MINT_POSITION,
///      SETTLE_PAIR, TAKE_PAIR, CLOSE_CURRENCY and SWEEP. Positions are keyed by (this, range, salt = tokenId).
contract FaithfulCLPositionManager is ERC721, IFaithfulLockCallback {
  using SafeERC20 for IERC20;
  using SlippageCheck for BalanceDelta;
  using PoolIdLibrary for PoolKey;
  using CLPositionInfoLibrary for CLPositionInfo;
  using InfinitySafeCast for uint256;

  error NotApproved(address caller);
  error DeadlinePassed(uint256 deadline);
  error UnsupportedAction(uint256 action);
  error DeltaNotPositive(Currency currency);
  error DeltaNotNegative(Currency currency);
  error InputLengthMismatch();
  error ContractLocked();
  error NativeValueUnsupported();
  error InvalidTokenID();

  FaithfulCLPoolManager internal immutable _manager;
  FaithfulPermit2 public immutable permit2;
  uint256 public nextTokenId = 1;
  mapping(uint256 tokenId => CLPositionInfo info) public positionInfo;
  mapping(bytes25 poolId => PoolKey poolKey) public poolKeys;
  address internal _locker;

  constructor(FaithfulCLPoolManager manager_, FaithfulPermit2 permit2_)
    ERC721("Pancake V4 Positions NFT", "PCS-V4-POSM")
  {
    _manager = manager_;
    permit2 = permit2_;
  }

  function clPoolManager() external view returns (address) {
    return address(_manager);
  }

  function vault() external view returns (address) {
    return address(_manager);
  }

  /// @dev CLPositionManager.modifyLiquidities: deadline check, reentrancy lock, the locker is `msgSender()`.
  function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable {
    if (block.timestamp > deadline) revert DeadlinePassed(deadline);
    if (_locker != address(0)) revert ContractLocked();
    if (msg.value != 0) revert NativeValueUnsupported();
    _locker = msg.sender;
    _manager.lock(payload);
    _locker = address(0);
  }

  /// @dev BaseActionsRouter._executeActionsWithoutLock.
  function lockAcquired(bytes calldata data) external returns (bytes memory) {
    require(msg.sender == address(_manager), "callback");
    (bytes memory actions, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));
    if (actions.length != params.length) revert InputLengthMismatch();
    for (uint256 i; i < actions.length; ++i) {
      _handleAction(uint8(actions[i]), params[i]);
    }
    return "";
  }

  function getPoolAndPositionInfo(uint256 tokenId) public view returns (PoolKey memory poolKey, CLPositionInfo info) {
    info = positionInfo[tokenId];
    poolKey = poolKeys[info.poolId()];
  }

  function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
    (PoolKey memory poolKey, CLPositionInfo info) = getPoolAndPositionInfo(tokenId);
    return
      _manager.getPosition(poolKey.toId(), address(this), info.tickLower(), info.tickUpper(), bytes32(tokenId))
      .liquidity;
  }

  /// @dev CLPositionManager.positions: reverts InvalidTokenID for an unknown id.
  function positions(uint256 tokenId)
    external
    view
    returns (
      PoolKey memory poolKey,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      address subscriber
    )
  {
    CLPositionInfo info;
    (poolKey, info) = getPoolAndPositionInfo(tokenId);
    if (CLPositionInfo.unwrap(info) == 0) revert InvalidTokenID();
    tickLower = info.tickLower();
    tickUpper = info.tickUpper();
    CLPosition.Info memory position =
      _manager.getPosition(poolKey.toId(), address(this), tickLower, tickUpper, bytes32(tokenId));
    liquidity = position.liquidity;
    feeGrowthInside0LastX128 = position.feeGrowthInside0LastX128;
    feeGrowthInside1LastX128 = position.feeGrowthInside1LastX128;
    subscriber = address(0);
  }

  /// @dev Test oracle: fees the pool will credit this NFT on its next modifyLiquidity.
  function pendingFees(uint256 tokenId) external view returns (uint256, uint256) {
    (PoolKey memory poolKey, CLPositionInfo info) = getPoolAndPositionInfo(tokenId);
    return _manager.pendingFees(poolKey, address(this), info.tickLower(), info.tickUpper(), bytes32(tokenId));
  }

  /// @dev CLPositionManager._handleAction for the supported actions.
  function _handleAction(uint256 action, bytes memory params) internal {
    if (action == Actions.CL_INCREASE_LIQUIDITY) {
      (uint256 tokenId, uint256 liquidity, uint128 amount0Max, uint128 amount1Max, bytes memory hookData) =
        abi.decode(params, (uint256, uint256, uint128, uint128, bytes));
      _modify(tokenId, liquidity.toInt256(), hookData).validateMaxIn(amount0Max, amount1Max);
    } else if (action == Actions.CL_DECREASE_LIQUIDITY) {
      (uint256 tokenId, uint256 liquidity, uint128 amount0Min, uint128 amount1Min, bytes memory hookData) =
        abi.decode(params, (uint256, uint256, uint128, uint128, bytes));
      _modify(tokenId, -(liquidity.toInt256()), hookData).validateMinOut(amount0Min, amount1Min);
    } else if (action == Actions.CL_MINT_POSITION) {
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
      // CLPositionManager._sweep (ERC-20 currencies only in this mock).
      (Currency currency, address to) = abi.decode(params, (Currency, address));
      if (Currency.unwrap(currency) == address(0)) revert NativeValueUnsupported();
      uint256 balance = IERC20(Currency.unwrap(currency)).balanceOf(address(this));
      if (balance > 0) IERC20(Currency.unwrap(currency)).safeTransfer(_mapRecipient(to), balance);
    } else {
      revert UnsupportedAction(action);
    }
  }

  /// @dev CLPositionManager._increase / _decrease: `onlyIfApproved(msgSender(), tokenId)`, then modifyLiquidity
  ///      with salt = tokenId. Returns the principal-only delta the slippage check is applied to.
  function _modify(uint256 tokenId, int256 liquidityChange, bytes memory hookData)
    internal
    returns (BalanceDelta principalDelta)
  {
    if (!_isAuthorized(_ownerOf(tokenId), _locker, tokenId)) revert NotApproved(_locker);
    (PoolKey memory poolKey, CLPositionInfo info) = getPoolAndPositionInfo(tokenId);
    (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) = _manager.modifyLiquidity(
      poolKey,
      ICLPoolManager.ModifyLiquidityParams({
        tickLower: info.tickLower(),
        tickUpper: info.tickUpper(),
        liquidityDelta: liquidityChange,
        salt: bytes32(tokenId)
      }),
      hookData
    );
    principalDelta = liquidityDelta - feesAccrued;
  }

  /// @dev CLPositionManager._mint: next id, position info, first-seen pool key, then the principal max-in check.
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
    CLPositionInfo info = CLPositionInfoLibrary.initialize(poolKey, tickLower, tickUpper);
    positionInfo[tokenId] = info;
    bytes25 poolId = info.poolId();
    if (address(poolKeys[poolId].poolManager) == address(0)) poolKeys[poolId] = poolKey;
    (BalanceDelta liquidityDelta,) = _manager.modifyLiquidity(
      poolKey,
      ICLPoolManager.ModifyLiquidityParams({
        tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidity.toInt256(), salt: bytes32(tokenId)
      }),
      hookData
    );
    liquidityDelta.validateMaxIn(amount0Max, amount1Max);
  }

  /// @dev DeltaResolver._settle + CLPositionManager._pay: vault.sync, Permit2 pull from the payer, vault.settle.
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
