// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Pool } from "@uniswap/v4-core/src/libraries/Pool.sol";
import { Position } from "@uniswap/v4-core/src/libraries/Position.sol";
import { Slot0, Slot0Library } from "@uniswap/v4-core/src/types/Slot0.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { SharedV4ValuationLib } from "../../contracts/shared-vault/libraries/SharedV4ValuationLib.sol";

/// @dev Slot-accurate PoolManager mock: a real `mapping(PoolId => Pool.State)` is laid out at slot 6
///      (matching `StateLibrary.POOLS_SLOT` in the production PoolManager) and `extsload` is a raw
///      `sload` passthrough — so `StateLibrary`'s slot derivations in `SharedV4ValuationLib` read this
///      mock exactly the way they read the real PoolManager. Setters write the canonical structs.
contract ValuationSlotMockPoolManager {
  using Slot0Library for Slot0;

  // Slots 0..5 padding so `pools` lands at slot 6 == StateLibrary.POOLS_SLOT.
  uint256[6] private _slotGap;
  mapping(PoolId => Pool.State) internal pools;

  function setSlot0(PoolId poolId, uint160 sqrtPriceX96, int24 tick) external {
    pools[poolId].slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick);
  }

  function setFeeGrowthGlobals(PoolId poolId, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) external {
    pools[poolId].feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
    pools[poolId].feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
  }

  function setTickFeeGrowthOutside(PoolId poolId, int24 tick, uint256 outside0X128, uint256 outside1X128) external {
    pools[poolId].ticks[tick].feeGrowthOutside0X128 = outside0X128;
    pools[poolId].ticks[tick].feeGrowthOutside1X128 = outside1X128;
  }

  function setPosition(
    PoolId poolId,
    address owner,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt,
    uint128 liquidity,
    uint256 feeGrowthInside0LastX128,
    uint256 feeGrowthInside1LastX128
  ) external {
    Position.State storage p = pools[poolId].positions[Position.calculatePositionKey(owner, tickLower, tickUpper, salt)];
    p.liquidity = liquidity;
    p.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
    p.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
  }

  function extsload(bytes32 slot) external view returns (bytes32 value) {
    assembly ("memory-safe") {
      value := sload(slot)
    }
  }

  function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
    values = new bytes32[](nSlots);
    for (uint256 i; i < nSlots; i++) {
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
    for (uint256 i; i < slots.length; i++) {
      bytes32 slot = slots[i];
      bytes32 value;
      assembly ("memory-safe") {
        value := sload(slot)
      }
      values[i] = value;
    }
  }
}

/// @dev Minimal POSM mock for the valuation lib: pool/position info, POSM-side liquidity (used for
///      the principal valuation), and a switch to make `getPoolAndPositionInfo` revert like the real
///      POSM does for a burned tokenId.
contract ValuationMockPosm {
  ValuationSlotMockPoolManager public immutable poolManager;
  PoolKey internal _poolKey;
  int24 internal _tickLower;
  int24 internal _tickUpper;
  bool internal _revertOnInfo;
  mapping(uint256 => uint128) internal _liquidity;

  constructor(ValuationSlotMockPoolManager manager, PoolKey memory poolKey, int24 tickLower, int24 tickUpper) {
    poolManager = manager;
    _poolKey = poolKey;
    _tickLower = tickLower;
    _tickUpper = tickUpper;
  }

  function setRevertOnInfo(bool shouldRevert) external {
    _revertOnInfo = shouldRevert;
  }

  function setLiquidity(uint256 tokenId, uint128 liquidity) external {
    _liquidity[tokenId] = liquidity;
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory poolKey, PositionInfo info) {
    require(!_revertOnInfo, "ERC721: invalid token ID");
    poolKey = _poolKey;
    info = PositionInfoLibrary.initialize(_poolKey, _tickLower, _tickUpper);
  }

  function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
    return _liquidity[tokenId];
  }
}

/// @notice First direct unit coverage for `SharedV4ValuationLib` — previously exercised only through
///         integration/fork paths. Pins the burned-token try/catch fallback, the principal/fee split,
///         the F7 wrapped-fee-growth no-revert guarantee, and every branch of the non-wrapping
///         `hasCollectableFeesForFailedCollect` gate.
contract SharedV4ValuationLibTest is Test {
  using PoolIdLibrary for PoolKey;

  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336; // 2^96, price 1:1
  uint256 internal constant Q128 = FixedPoint128.Q128;
  int24 internal constant TICK_LOWER = -60;
  int24 internal constant TICK_UPPER = 60;
  uint256 internal constant TOKEN_ID = 42;

  ValuationSlotMockPoolManager internal manager;
  ValuationMockPosm internal posm;
  PoolKey internal poolKey;
  PoolId internal poolId;

  function setUp() public {
    manager = new ValuationSlotMockPoolManager();
    poolKey = PoolKey({
      currency0: Currency.wrap(address(0x1111)),
      currency1: Currency.wrap(address(0x2222)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });
    poolId = poolKey.toId();
    posm = new ValuationMockPosm(manager, poolKey, TICK_LOWER, TICK_UPPER);
    manager.setSlot0(poolId, SQRT_PRICE_1_1, 0); // in-range: TICK_LOWER <= 0 < TICK_UPPER
  }

  /// @dev Seeds an in-range position with the SAME liquidity snapshot on both sides (POSM-side for
  ///      principal, manager-side for fee accrual) plus a last-fee-growth checkpoint of zero.
  function _seedPosition(uint128 liquidity, uint256 lastFeeGrowth0, uint256 lastFeeGrowth1) internal {
    posm.setLiquidity(TOKEN_ID, liquidity);
    manager.setPosition(
      poolId, address(posm), TICK_LOWER, TICK_UPPER, bytes32(TOKEN_ID), liquidity, lastFeeGrowth0, lastFeeGrowth1
    );
  }

  function _expectedPrincipal(uint128 liquidity) internal pure returns (uint256 amount0, uint256 amount1) {
    return LiquidityAmounts.getAmountsForLiquidity(
      SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(TICK_LOWER), TickMath.getSqrtPriceAtTick(TICK_UPPER), liquidity
    );
  }

  // ==================== Burned / invalid tokenId fallback ====================

  /// @dev The try/catch around `getPoolAndPositionInfo` exists so a burned tokenId values to zero
  ///      instead of reverting — an unguarded revert here would brick `deposit()`/`withdraw()`/preview
  ///      for the whole vault while the stale position is still tracked.
  function test_getPositionAmounts_returnsZeros_whenPositionInfoLookupReverts() public {
    _seedPosition(1e18, 0, 0);
    posm.setRevertOnInfo(true);

    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);
    assertEq(amount0, 0, "burned token values to zero, not a revert");
    assertEq(amount1, 0);

    (uint256 p0, uint256 p1) = SharedV4ValuationLib.getPositionPrincipalAmounts(address(posm), TOKEN_ID);
    assertEq(p0, 0);
    assertEq(p1, 0);

    (uint256 t0, uint256 t1, uint256 pp0, uint256 pp1) =
      SharedV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);
    assertEq(t0, 0);
    assertEq(t1, 0);
    assertEq(pp0, 0);
    assertEq(pp1, 0);
  }

  // ==================== Principal / fee split ====================

  /// @dev Known-math pin: liquidity 1e18 in [-60, 60] at price 1:1 plus a fee-growth-inside delta of
  ///      exactly Q128 (token0) and 2·Q128 (token1) per unit liquidity → uncollected fees of exactly
  ///      1e18 / 2e18 (mulDiv(delta, L, Q128) with no flooring loss).
  function test_getPositionAmountsSplit_separatesPrincipalAndFees() public {
    uint128 liquidity = 1e18;
    _seedPosition(liquidity, 0, 0);
    // tick outsides default to zero and current tick 0 is inside the range, so feeGrowthInside == globals.
    manager.setFeeGrowthGlobals(poolId, Q128, 2 * Q128);

    (uint256 expected0, uint256 expected1) = _expectedPrincipal(liquidity);
    assertGt(expected0, 0, "sanity: position has token0 principal");
    assertEq(expected0, expected1, "symmetric range at 1:1 price holds equal principal");

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      SharedV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);

    assertEq(principal0, expected0, "principal0 from liquidity at spot price");
    assertEq(principal1, expected1, "principal1 from liquidity at spot price");
    assertEq(total0 - principal0, 1e18, "fees0 = Q128 delta * 1e18 liquidity / Q128");
    assertEq(total1 - principal1, 2e18, "fees1 = 2*Q128 delta * 1e18 liquidity / Q128");
  }

  function test_getPositionPrincipalAmounts_excludesUncollectedFees() public {
    uint128 liquidity = 1e18;
    _seedPosition(liquidity, 0, 0);
    manager.setFeeGrowthGlobals(poolId, Q128, Q128);

    (uint256 principal0, uint256 principal1) =
      SharedV4ValuationLib.getPositionPrincipalAmounts(address(posm), TOKEN_ID);
    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);

    (uint256 expected0, uint256 expected1) = _expectedPrincipal(liquidity);
    assertEq(principal0, expected0, "principal getter excludes fees");
    assertEq(principal1, expected1);
    assertEq(amount0, principal0 + 1e18, "total getter adds the fee slice");
    assertEq(amount1, principal1 + 1e18);
  }

  /// @dev Position liquidity 0 short-circuits both the principal branch and `_uncollectedFees`,
  ///      even when the pool has accrued global fee growth.
  function test_getPositionAmounts_zeroLiquidity_returnsZeros() public {
    manager.setFeeGrowthGlobals(poolId, 5 * Q128, 5 * Q128);

    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);
    assertEq(amount0, 0);
    assertEq(amount1, 0);
  }

  /// @dev F7 pin: with a checkpoint AHEAD of current fee growth (possible after fee-growth wrap),
  ///      `_feeOwed`'s unchecked subtraction wraps mod 2^256 by design — and valuation must NOT
  ///      revert, because a reverting valuation bricks deposits for the whole vault. The wrapped
  ///      delta 0 - Q128 ≡ 2^128·(2^128 − 1), so the fee term is exactly (2^128 − 1)·liquidity.
  function test_getPositionAmounts_wrappedFeeGrowth_doesNotRevert() public {
    uint128 liquidity = 1e18;
    _seedPosition(liquidity, Q128, 0); // token0 checkpoint ahead of the (zero) current growth
    (uint256 expected0,) = _expectedPrincipal(liquidity);

    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(address(posm), TOKEN_ID);

    assertEq(amount0, expected0 + (Q128 - 1) * uint256(liquidity), "wrapped delta valued mod 2^256, no revert");
    assertEq(amount1, expected0, "token1 checkpoint not wrapped: principal only");
  }

  // ==================== Fee-growth-inside decomposition (out-of-range branches) ====================
  // V4 delegates fee-growth-inside to StateLibrary; pin both out-of-range branches anyway so the lib's
  // wiring through tick snapshots stays mirrored with the Pancake twin's hand-rolled decomposition.

  /// @dev Current tick BELOW the range: inside = lower.outside − upper.outside (globals cancel).
  function test_feeGrowthInside_currentTickBelowRange() public {
    uint128 liquidity = 1e18;
    int24 tickCurrent = -120; // < TICK_LOWER
    manager.setSlot0(poolId, TickMath.getSqrtPriceAtTick(tickCurrent), tickCurrent);
    manager.setFeeGrowthGlobals(poolId, 100 * Q128, 100 * Q128);
    manager.setTickFeeGrowthOutside(poolId, TICK_LOWER, 7 * Q128, 9 * Q128);
    manager.setTickFeeGrowthOutside(poolId, TICK_UPPER, 3 * Q128, 4 * Q128);
    _seedPosition(liquidity, 0, 0);

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      SharedV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);

    assertEq(total0 - principal0, 4e18, "inside0 = (7-3)*Q128 -> 4e18 fees on 1e18 liquidity");
    assertEq(total1 - principal1, 5e18, "inside1 = (9-4)*Q128 -> 5e18 fees on 1e18 liquidity");
    assertEq(principal1, 0, "below range: principal entirely in token0");
    assertGt(principal0, 0);
  }

  /// @dev Current tick AT/ABOVE the range: inside = upper.outside − lower.outside (globals cancel).
  function test_feeGrowthInside_currentTickAboveRange() public {
    uint128 liquidity = 1e18;
    int24 tickCurrent = 120; // >= TICK_UPPER
    manager.setSlot0(poolId, TickMath.getSqrtPriceAtTick(tickCurrent), tickCurrent);
    manager.setFeeGrowthGlobals(poolId, 100 * Q128, 100 * Q128);
    manager.setTickFeeGrowthOutside(poolId, TICK_LOWER, 4 * Q128, 1 * Q128);
    manager.setTickFeeGrowthOutside(poolId, TICK_UPPER, 9 * Q128, 7 * Q128);
    _seedPosition(liquidity, 0, 0);

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      SharedV4ValuationLib.getPositionAmountsSplit(address(posm), TOKEN_ID);

    assertEq(total0 - principal0, 5e18, "inside0 = (9-4)*Q128 -> 5e18 fees on 1e18 liquidity");
    assertEq(total1 - principal1, 6e18, "inside1 = (7-1)*Q128 -> 6e18 fees on 1e18 liquidity");
    assertEq(principal0, 0, "above range: principal entirely in token1");
    assertGt(principal1, 0);
  }

  // ==================== hasCollectableFeesForFailedCollect ====================

  function test_hasCollectableFees_falseWhenLiquidityZero() public {
    posm.setLiquidity(TOKEN_ID, 1e18); // POSM-side liquidity is irrelevant here
    manager.setFeeGrowthGlobals(poolId, 10 * Q128, 10 * Q128);
    // manager-side position liquidity stays zero

    assertFalse(SharedV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  /// @dev The gate uses a NON-wrapping delta check (unlike `_feeOwed`): a checkpoint ahead of
  ///      current growth must read as "no collectable fees" — not as near-2^256 pending fees that
  ///      would re-throw a tolerated hook failure and brick a zero-fee position.
  function test_hasCollectableFees_falseOnWrappedFeeGrowth() public {
    _seedPosition(1e18, Q128, Q128); // checkpoints ahead, current growth zero

    assertFalse(SharedV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  /// @dev A positive delta whose fee floors to zero wei (delta 1, liquidity 1 → mulDiv = 0) is not
  ///      collectable: the gate must agree with what a collect would actually pay out.
  function test_hasCollectableFees_falseWhenDeltaFloorsToZeroWei() public {
    _seedPosition(1, 0, 0);
    manager.setFeeGrowthGlobals(poolId, 1, 1);

    assertFalse(SharedV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  function test_hasCollectableFees_trueOnPositiveDelta() public {
    _seedPosition(1e18, 0, 0);
    manager.setFeeGrowthGlobals(poolId, Q128, 0);

    assertTrue(SharedV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }

  /// @dev The gate ORs both tokens: a token1-only delta must trip it even with token0 at zero.
  function test_hasCollectableFees_trueOnToken1OnlyDelta() public {
    _seedPosition(1e18, 0, 0);
    manager.setFeeGrowthGlobals(poolId, 0, Q128);

    assertTrue(SharedV4ValuationLib.hasCollectableFeesForFailedCollect(address(posm), TOKEN_ID));
  }
}
