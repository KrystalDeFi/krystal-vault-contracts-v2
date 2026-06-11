// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { Currency } from "infinity-core/src/types/Currency.sol";
import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { PoolId } from "infinity-core/src/types/PoolId.sol";
import { IHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import { Tick } from "infinity-core/src/pool-cl/libraries/Tick.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";

import { SharedPancakeV4ValuationLib } from "../../contracts/shared-vault/libraries/SharedPancakeV4ValuationLib.sol";

/// @dev CL pool manager mock with directly-settable slot0, tick fee-growth-outside snapshots, and
///      fee-growth globals — the three reads `SharedPancakeV4ValuationLib._getFeeGrowthInside` makes
///      (PancakeSwap Infinity exposes these as plain view getters, unlike Uniswap V4's extsload).
contract PancakeValuationMockPoolManager {
  uint160 internal _sqrtPriceX96;
  int24 internal _tick;
  uint256 internal _feeGrowthGlobal0X128;
  uint256 internal _feeGrowthGlobal1X128;
  mapping(int24 => Tick.Info) internal _ticks;

  function setSlot0(uint160 sqrtPriceX96, int24 tick) external {
    _sqrtPriceX96 = sqrtPriceX96;
    _tick = tick;
  }

  function setFeeGrowthGlobals(uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) external {
    _feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
    _feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
  }

  function setTickFeeGrowthOutside(int24 tick, uint256 outside0X128, uint256 outside1X128) external {
    _ticks[tick].feeGrowthOutside0X128 = outside0X128;
    _ticks[tick].feeGrowthOutside1X128 = outside1X128;
  }

  function getSlot0(PoolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24, uint24) {
    return (_sqrtPriceX96, _tick, 0, 0);
  }

  function getPoolTickInfo(PoolId, int24 tick) external view returns (Tick.Info memory) {
    return _ticks[tick];
  }

  function getFeeGrowthGlobals(PoolId) external view returns (uint256, uint256) {
    return (_feeGrowthGlobal0X128, _feeGrowthGlobal1X128);
  }
}

/// @dev Minimal CLPositionManager mock: pool/position info (with switches for the burned-token revert
///      and the empty-CLPositionInfo states) plus the `positions()` read the lib snapshots liquidity
///      and last-fee-growth from. `revertOnPositions` mimics the real CLPositionManager, which reverts
///      `InvalidTokenID()` on `positions()` for an empty position — proving the lib short-circuits.
contract PancakeValuationMockPosm {
  PancakeValuationMockPoolManager public immutable poolManager;
  PoolKey internal _poolKey;
  int24 internal _tickLower;
  int24 internal _tickUpper;
  bool internal _revertOnInfo;
  bool internal _emptyInfo;
  bool internal _revertOnPositions;
  mapping(uint256 => uint128) internal _liquidity;
  mapping(uint256 => uint256) internal _lastFeeGrowth0;
  mapping(uint256 => uint256) internal _lastFeeGrowth1;

  constructor(PancakeValuationMockPoolManager manager, PoolKey memory poolKey, int24 tickLower, int24 tickUpper) {
    poolManager = manager;
    _poolKey = poolKey;
    _tickLower = tickLower;
    _tickUpper = tickUpper;
  }

  function setRevertOnInfo(bool shouldRevert) external {
    _revertOnInfo = shouldRevert;
  }

  function setEmptyInfo(bool empty) external {
    _emptyInfo = empty;
  }

  function setRevertOnPositions(bool shouldRevert) external {
    _revertOnPositions = shouldRevert;
  }

  function setPosition(uint256 tokenId, uint128 liquidity, uint256 lastFeeGrowth0, uint256 lastFeeGrowth1) external {
    _liquidity[tokenId] = liquidity;
    _lastFeeGrowth0[tokenId] = lastFeeGrowth0;
    _lastFeeGrowth1[tokenId] = lastFeeGrowth1;
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory poolKey, CLPositionInfo info) {
    require(!_revertOnInfo, "ERC721: invalid token ID");
    poolKey = _poolKey;
    info = _emptyInfo ? CLPositionInfo.wrap(0) : CLPositionInfoLibrary.initialize(_poolKey, _tickLower, _tickUpper);
  }

  function positions(uint256 tokenId)
    external
    view
    returns (PoolKey memory poolKey, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256, uint256, address)
  {
    require(!_revertOnPositions, "InvalidTokenID");
    return (
      _poolKey, _tickLower, _tickUpper, _liquidity[tokenId], _lastFeeGrowth0[tokenId], _lastFeeGrowth1[tokenId],
      address(0)
    );
  }
}

/// @notice First direct unit coverage for `SharedPancakeV4ValuationLib` — the fork twin of
///         `SharedV4ValuationLib.t.sol` (fix/extend both together). Adds Pancake-specific pins for the
///         empty-CLPositionInfo brick-guard and the hand-rolled `_getFeeGrowthInside` decomposition,
///         which the Uniswap V4 sibling delegates to the battle-tested `StateLibrary`.
contract SharedPancakeV4ValuationLibTest is Test {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336; // 2^96, price 1:1
  uint256 internal constant Q128 = FixedPoint128.Q128;
  int24 internal constant TICK_LOWER = -60;
  int24 internal constant TICK_UPPER = 60;
  uint256 internal constant TOKEN_ID = 42;

  PancakeValuationMockPoolManager internal manager;
  PancakeValuationMockPosm internal posm;

  function setUp() public {
    manager = new PancakeValuationMockPoolManager();
    PoolKey memory poolKey = PoolKey({
      currency0: Currency.wrap(address(0x1111)),
      currency1: Currency.wrap(address(0x2222)),
      hooks: IHooks(address(0)),
      poolManager: IPoolManager(address(manager)),
      fee: 3000,
      parameters: bytes32(uint256(uint24(60)) << 16) // tickSpacing 60
    });
    posm = new PancakeValuationMockPosm(manager, poolKey, TICK_LOWER, TICK_UPPER);
    manager.setSlot0(SQRT_PRICE_1_1, 0); // in-range: TICK_LOWER <= 0 < TICK_UPPER
  }

  function _expectedPrincipal(uint160 sqrtPriceX96, uint128 liquidity)
    internal
    pure
    returns (uint256 amount0, uint256 amount1)
  {
    return LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96, TickMath.getSqrtPriceAtTick(TICK_LOWER), TickMath.getSqrtPriceAtTick(TICK_UPPER), liquidity
    );
  }

  // ==================== Burned / empty tokenId fallbacks ====================

  function test_getPositionAmounts_returnsZeros_whenPositionInfoLookupReverts() public {
    posm.setPosition(TOKEN_ID, 1e18, 0, 0);
    posm.setRevertOnInfo(true);

    (uint256 amount0, uint256 amount1) = SharedPancakeV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);
    assertEq(amount0, 0, "burned token values to zero, not a revert");
    assertEq(amount1, 0);
  }

  /// @dev Pancake-specific brick-guard: `getPoolAndPositionInfo` returns a ZERO `CLPositionInfo` for an
  ///      empty tokenId WITHOUT reverting, while `positions()` for that tokenId reverts `InvalidTokenID()`.
  ///      The lib must short-circuit on the zero info — proven here by arming the mock to revert in
  ///      `positions()`: if the lib ever called it, this test would revert instead of returning zeros.
  function test_getPositionAmounts_returnsZeros_whenPositionInfoIsEmpty_withoutTouchingPositions() public {
    posm.setEmptyInfo(true);
    posm.setRevertOnPositions(true);

    (uint256 amount0, uint256 amount1) = SharedPancakeV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);
    assertEq(amount0, 0, "empty CLPositionInfo short-circuits to zero before positions()");
    assertEq(amount1, 0);

    (uint256 t0, uint256 t1, uint256 p0, uint256 p1) =
      SharedPancakeV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);
    assertEq(t0, 0);
    assertEq(t1, 0);
    assertEq(p0, 0);
    assertEq(p1, 0);
  }

  function test_hasCollectableFees_falseWhenPositionInfoIsEmpty() public {
    posm.setEmptyInfo(true);
    posm.setRevertOnPositions(true);

    assertFalse(SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  // ==================== Principal / fee split ====================

  /// @dev Same known-math pin as the V4 twin: liquidity 1e18 in [-60, 60] at price 1:1 plus a
  ///      fee-growth-inside delta of Q128 / 2·Q128 per unit liquidity → fees of exactly 1e18 / 2e18.
  function test_getPositionAmountsSplit_separatesPrincipalAndFees() public {
    uint128 liquidity = 1e18;
    posm.setPosition(TOKEN_ID, liquidity, 0, 0);
    manager.setFeeGrowthGlobals(Q128, 2 * Q128); // outsides zero, tick 0 in range → inside == globals

    (uint256 expected0, uint256 expected1) = _expectedPrincipal(SQRT_PRICE_1_1, liquidity);
    assertGt(expected0, 0, "sanity: position has token0 principal");
    assertEq(expected0, expected1, "symmetric range at 1:1 price holds equal principal");

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      SharedPancakeV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);

    assertEq(principal0, expected0, "principal0 from liquidity at spot price");
    assertEq(principal1, expected1, "principal1 from liquidity at spot price");
    assertEq(total0 - principal0, 1e18, "fees0 = Q128 delta * 1e18 liquidity / Q128");
    assertEq(total1 - principal1, 2e18, "fees1 = 2*Q128 delta * 1e18 liquidity / Q128");
  }

  function test_getPositionPrincipalAmounts_excludesUncollectedFees() public {
    uint128 liquidity = 1e18;
    posm.setPosition(TOKEN_ID, liquidity, 0, 0);
    manager.setFeeGrowthGlobals(Q128, Q128);

    (uint256 principal0, uint256 principal1) =
      SharedPancakeV4ValuationLib.getPositionPrincipalAmounts(address(posm), TOKEN_ID);
    (uint256 amount0, uint256 amount1) = SharedPancakeV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);

    (uint256 expected0, uint256 expected1) = _expectedPrincipal(SQRT_PRICE_1_1, liquidity);
    assertEq(principal0, expected0, "principal getter excludes fees");
    assertEq(principal1, expected1);
    assertEq(amount0, principal0 + 1e18, "total getter adds the fee slice");
    assertEq(amount1, principal1 + 1e18);
  }

  function test_getPositionAmounts_zeroLiquidity_returnsZeros() public {
    manager.setFeeGrowthGlobals(5 * Q128, 5 * Q128);
    // position exists (non-empty info) but has zero liquidity

    (uint256 amount0, uint256 amount1) = SharedPancakeV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);
    assertEq(amount0, 0);
    assertEq(amount1, 0);
  }

  /// @dev F7 pin (parity with the V4 twin): a checkpoint AHEAD of current fee growth wraps mod 2^256
  ///      in `_feeOwed` by design and must NOT revert — a reverting valuation bricks deposits for the
  ///      whole vault. Wrapped delta 0 - Q128 ≡ 2^128·(2^128 − 1) → fee term (2^128 − 1)·liquidity.
  function test_getPositionAmounts_wrappedFeeGrowth_doesNotRevert() public {
    uint128 liquidity = 1e18;
    posm.setPosition(TOKEN_ID, liquidity, Q128, 0); // token0 checkpoint ahead of zero current growth
    (uint256 expected0,) = _expectedPrincipal(SQRT_PRICE_1_1, liquidity);

    (uint256 amount0, uint256 amount1) = SharedPancakeV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);

    assertEq(amount0, expected0 + (Q128 - 1) * uint256(liquidity), "wrapped delta valued mod 2^256, no revert");
    assertEq(amount1, expected0, "token1 checkpoint not wrapped: principal only");
  }

  // ==================== Hand-rolled _getFeeGrowthInside decomposition ====================
  // PancakeSwap Infinity's CL PoolManager has no getFeeGrowthInside getter, so the lib reconstructs
  // [global - below - above] from boundary-tick snapshots itself. Pin both out-of-range branches.

  /// @dev Current tick BELOW the range: inside = lower.outside − upper.outside (globals cancel).
  function test_feeGrowthInside_currentTickBelowRange() public {
    uint128 liquidity = 1e18;
    int24 tickCurrent = -120; // < TICK_LOWER
    manager.setSlot0(TickMath.getSqrtPriceAtTick(tickCurrent), tickCurrent);
    manager.setFeeGrowthGlobals(100 * Q128, 100 * Q128);
    manager.setTickFeeGrowthOutside(TICK_LOWER, 7 * Q128, 9 * Q128);
    manager.setTickFeeGrowthOutside(TICK_UPPER, 3 * Q128, 4 * Q128);
    posm.setPosition(TOKEN_ID, liquidity, 0, 0);

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      SharedPancakeV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);

    assertEq(total0 - principal0, 4e18, "inside0 = (7-3)*Q128 -> 4e18 fees on 1e18 liquidity");
    assertEq(total1 - principal1, 5e18, "inside1 = (9-4)*Q128 -> 5e18 fees on 1e18 liquidity");
    assertEq(principal1, 0, "below range: principal entirely in token0");
    assertGt(principal0, 0);
  }

  /// @dev Current tick AT/ABOVE the range: inside = upper.outside − lower.outside (globals cancel).
  function test_feeGrowthInside_currentTickAboveRange() public {
    uint128 liquidity = 1e18;
    int24 tickCurrent = 120; // >= TICK_UPPER
    manager.setSlot0(TickMath.getSqrtPriceAtTick(tickCurrent), tickCurrent);
    manager.setFeeGrowthGlobals(100 * Q128, 100 * Q128);
    manager.setTickFeeGrowthOutside(TICK_LOWER, 4 * Q128, 1 * Q128);
    manager.setTickFeeGrowthOutside(TICK_UPPER, 9 * Q128, 7 * Q128);
    posm.setPosition(TOKEN_ID, liquidity, 0, 0);

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      SharedPancakeV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);

    assertEq(total0 - principal0, 5e18, "inside0 = (9-4)*Q128 -> 5e18 fees on 1e18 liquidity");
    assertEq(total1 - principal1, 6e18, "inside1 = (7-1)*Q128 -> 6e18 fees on 1e18 liquidity");
    assertEq(principal0, 0, "above range: principal entirely in token1");
    assertGt(principal1, 0);
  }

  // ==================== hasCollectableFeesForFailedCollect ====================

  function test_hasCollectableFees_falseWhenLiquidityZero() public {
    manager.setFeeGrowthGlobals(10 * Q128, 10 * Q128);
    // non-empty position info, zero liquidity

    assertFalse(SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  /// @dev Non-wrapping gate (unlike `_feeOwed`): a checkpoint ahead of current growth reads as
  ///      "no collectable fees" — not near-2^256 pending fees that would re-throw a tolerated hook
  ///      failure and brick a zero-fee position.
  function test_hasCollectableFees_falseOnWrappedFeeGrowth() public {
    posm.setPosition(TOKEN_ID, 1e18, Q128, Q128); // checkpoints ahead, current growth zero

    assertFalse(SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  function test_hasCollectableFees_falseWhenDeltaFloorsToZeroWei() public {
    posm.setPosition(TOKEN_ID, 1, 0, 0);
    manager.setFeeGrowthGlobals(1, 1); // delta 1, liquidity 1 -> mulDiv floors to 0

    assertFalse(SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  function test_hasCollectableFees_trueOnPositiveDelta() public {
    posm.setPosition(TOKEN_ID, 1e18, 0, 0);
    manager.setFeeGrowthGlobals(Q128, 0);

    assertTrue(SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  function test_hasCollectableFees_trueOnToken1OnlyDelta() public {
    posm.setPosition(TOKEN_ID, 1e18, 0, 0);
    manager.setFeeGrowthGlobals(0, Q128);

    assertTrue(SharedPancakeV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }
}
