// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";

/// @title Live-liquidity valuation coverage for SharedV3Strategy.getPositionAmounts (MED-1)
/// @notice Before this file, the V3/Aerodrome valuation path (`_positionAmountsSplit` →
///         `getAmountsForLiquidity` for principal + `_getFeeGrowthInside` for uncollected fees) was only
///         ever exercised through the `liquidity == 0` / burned-NFT short-circuits. The core
///         concentrated-liquidity math — which feeds vault NAV, `previewWithdraw`, and deposit share
///         pricing — had ZERO coverage with a position that actually holds liquidity.
///
///         The whole valuation is driven through `vm.mockCall` against the standard Uniswap-v3
///         `positions()` / `slot0()` / `ticks()` / `feeGrowthGlobal*()` reads, so the strategy's real
///         decode + math runs unmodified. To stay non-tautological:
///           - PRINCIPAL is asserted against an independent call to the canonical `LiquidityAmounts`
///             library (Uniswap's math, not the strategy's logic). This still catches a strategy that
///             mis-decodes slot0, swaps the tick bounds, or passes the wrong liquidity.
///           - FEES are pinned to hand-derived numbers using the closed forms of the fee-growth-inside
///             formula at known positions: in-range with zero tick-outsides => inside == global; below
///             range => inside == lowerOutside − upperOutside; above range => inside == upperOutside −
///             lowerOutside. With liquidity == 1e18, `mulDiv(k·Q128, 1e18, Q128) == k·1e18`, so a fee
///             growth of `k·Q128` yields exactly `k ether` of owed token — no library call needed.
contract SharedV3StrategyValuationTest is Test {
  uint256 internal constant Q128 = 0x100000000000000000000000000000000; // 2**128

  SharedV3Strategy internal strategy;

  address internal constant NFPM = address(0x4001);
  address internal constant FACTORY = address(0x4002);
  address internal constant POOL = address(0x4003);
  address internal constant TOKEN0 = address(0x7000);
  address internal constant TOKEN1 = address(0x7001);
  uint24 internal constant FEE = 3000;
  uint256 internal constant TOKEN_ID = 42;

  // Liquidity chosen as 1e18 so `mulDiv(k·Q128, liquidity, Q128) == k·1e18` exactly.
  uint128 internal constant L = 1e18;

  struct PosCfg {
    int24 tickLower;
    int24 tickUpper;
    int24 tickCurrent;
    uint256 fg0Global;
    uint256 fg1Global;
    uint256 lowerOut0;
    uint256 lowerOut1;
    uint256 upperOut0;
    uint256 upperOut1;
    uint256 fg0Last;
    uint256 fg1Last;
    uint128 owed0;
    uint128 owed1;
  }

  function setUp() public {
    strategy = new SharedV3Strategy(address(0x9001));
  }

  /// @dev Wire every external read `_positionAmountsSplit` performs to a mocked value.
  function _mockPosition(PosCfg memory c) internal {
    uint160 sqrtP = TickMath.getSqrtRatioAtTick(c.tickCurrent);

    vm.mockCall(
      NFPM,
      abi.encodeWithSignature("positions(uint256)", TOKEN_ID),
      abi.encode(
        uint96(0), address(0), TOKEN0, TOKEN1, FEE, c.tickLower, c.tickUpper, L, c.fg0Last, c.fg1Last, c.owed0, c.owed1
      )
    );
    vm.mockCall(NFPM, abi.encodeWithSignature("factory()"), abi.encode(FACTORY));
    vm.mockCall(
      FACTORY, abi.encodeWithSignature("getPool(address,address,uint24)", TOKEN0, TOKEN1, FEE), abi.encode(POOL)
    );
    // V3 slot0 is read by the strategy via staticcall + assembly (words 0,1 = sqrtPriceX96, tick).
    vm.mockCall(
      POOL,
      abi.encodeWithSignature("slot0()"),
      abi.encode(uint160(sqrtP), c.tickCurrent, uint16(0), uint16(0), uint16(0), uint8(0), false)
    );
    vm.mockCall(POOL, abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(c.fg0Global));
    vm.mockCall(POOL, abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(c.fg1Global));
    // V3 ticks() 8-tuple: feeGrowthOutside0/1X128 at indices 2,3.
    vm.mockCall(
      POOL,
      abi.encodeWithSignature("ticks(int24)", c.tickLower),
      abi.encode(uint128(0), int128(0), c.lowerOut0, c.lowerOut1, int56(0), uint160(0), uint32(0), false)
    );
    vm.mockCall(
      POOL,
      abi.encodeWithSignature("ticks(int24)", c.tickUpper),
      abi.encode(uint128(0), int128(0), c.upperOut0, c.upperOut1, int56(0), uint160(0), uint32(0), false)
    );
  }

  function _expectedPrincipal(PosCfg memory c) internal pure returns (uint256 p0, uint256 p1) {
    (p0, p1) = LiquidityAmounts.getAmountsForLiquidity(
      TickMath.getSqrtRatioAtTick(c.tickCurrent),
      TickMath.getSqrtRatioAtTick(c.tickLower),
      TickMath.getSqrtRatioAtTick(c.tickUpper),
      L
    );
  }

  // ============================================================================================
  // In-range: principal balanced across both tokens, fees == feeGrowthGlobal (zero tick-outsides).
  // ============================================================================================
  function test_getPositionAmounts_inRange_pinsPrincipalAndFees() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: 0, // in range
      fg0Global: 3 * Q128,
      fg1Global: 4 * Q128,
      lowerOut0: 0,
      lowerOut1: 0,
      upperOut0: 0,
      upperOut1: 0,
      fg0Last: 0,
      fg1Last: 0,
      owed0: 0,
      owed1: 0
    });
    _mockPosition(c);

    (uint256 expP0, uint256 expP1) = _expectedPrincipal(c);
    assertGt(expP0, 0, "sanity: in-range principal0 > 0");
    assertGt(expP1, 0, "sanity: in-range principal1 > 0");

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(NFPM, TOKEN_ID);

    // Principal: independent canonical-library check.
    assertEq(principal0, expP0, "principal0 matches canonical LiquidityAmounts");
    assertEq(principal1, expP1, "principal1 matches canonical LiquidityAmounts");

    // Fees: in-range with zero outsides => inside == global => k·1e18.
    assertEq(total0 - principal0, 3 ether, "fee0 == feeGrowthGlobal0 * L / Q128");
    assertEq(total1 - principal1, 4 ether, "fee1 == feeGrowthGlobal1 * L / Q128");

    // getPositionAmounts must equal split totals.
    (uint256 amt0, uint256 amt1) = strategy.getPositionAmounts(NFPM, TOKEN_ID);
    assertEq(amt0, total0, "getPositionAmounts.amount0 == split total0");
    assertEq(amt1, total1, "getPositionAmounts.amount1 == split total1");
  }

  // ============================================================================================
  // In-range, with a non-zero feeGrowthInsideLast (delta subtraction) AND pre-accrued tokensOwed.
  // ============================================================================================
  function test_getPositionAmounts_subtractsFeeGrowthLast_andAddsOwed() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: 0,
      fg0Global: 3 * Q128,
      fg1Global: 5 * Q128,
      lowerOut0: 0,
      lowerOut1: 0,
      upperOut0: 0,
      upperOut1: 0,
      fg0Last: 1 * Q128, // delta0 = (3 - 1)·Q128 => fee 2 ether
      fg1Last: 2 * Q128, // delta1 = (5 - 2)·Q128 => fee 3 ether
      owed0: 0.5 ether, // added on top
      owed1: 0.25 ether
    });
    _mockPosition(c);

    (uint256 expP0, uint256 expP1) = _expectedPrincipal(c);
    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(NFPM, TOKEN_ID);

    assertEq(principal0, expP0, "principal0");
    assertEq(principal1, expP1, "principal1");
    // tokensOwed = owed + (global - last)·L/Q128
    assertEq(total0 - principal0, 0.5 ether + 2 ether, "fee0 = owed0 + delta0");
    assertEq(total1 - principal1, 0.25 ether + 3 ether, "fee1 = owed1 + delta1");
  }

  // ============================================================================================
  // Below range (tickCurrent < tickLower): exercises the `global - lowerOutside` branch of
  // _getFeeGrowthInside. Closed form: inside == lowerOutside - upperOutside. Principal all token0.
  // ============================================================================================
  function test_getPositionAmounts_belowRange_feeGrowthBranch() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: -1200, // below range
      fg0Global: 10 * Q128,
      fg1Global: 10 * Q128,
      lowerOut0: 4 * Q128,
      lowerOut1: 6 * Q128,
      upperOut0: 1 * Q128,
      upperOut1: 1 * Q128,
      fg0Last: 0,
      fg1Last: 0,
      owed0: 0,
      owed1: 0
    });
    _mockPosition(c);

    (uint256 expP0, uint256 expP1) = _expectedPrincipal(c);
    assertGt(expP0, 0, "below range => all token0");
    assertEq(expP1, 0, "below range => zero token1 principal");

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(NFPM, TOKEN_ID);

    assertEq(principal0, expP0, "principal0 (canonical)");
    assertEq(principal1, expP1, "principal1 == 0");
    // inside0 = lowerOut0 - upperOut0 = (4 - 1)·Q128 => 3 ether ; inside1 = (6 - 1) => 5 ether
    assertEq(total0 - principal0, 3 ether, "below-range fee0");
    assertEq(total1 - principal1, 5 ether, "below-range fee1");
  }

  // ============================================================================================
  // Above range (tickCurrent >= tickUpper): exercises the `global - upperOutside` branch.
  // Closed form: inside == upperOutside - lowerOutside. Principal all token1.
  // ============================================================================================
  function test_getPositionAmounts_aboveRange_feeGrowthBranch() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: 1200, // above range
      fg0Global: 10 * Q128,
      fg1Global: 10 * Q128,
      lowerOut0: 1 * Q128,
      lowerOut1: 1 * Q128,
      upperOut0: 4 * Q128,
      upperOut1: 7 * Q128,
      fg0Last: 0,
      fg1Last: 0,
      owed0: 0,
      owed1: 0
    });
    _mockPosition(c);

    (uint256 expP0, uint256 expP1) = _expectedPrincipal(c);
    assertEq(expP0, 0, "above range => zero token0 principal");
    assertGt(expP1, 0, "above range => all token1");

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(NFPM, TOKEN_ID);

    assertEq(principal0, expP0, "principal0 == 0");
    assertEq(principal1, expP1, "principal1 (canonical)");
    // inside0 = upperOut0 - lowerOut0 = (4 - 1) => 3 ether ; inside1 = (7 - 1) => 6 ether
    assertEq(total0 - principal0, 3 ether, "above-range fee0");
    assertEq(total1 - principal1, 6 ether, "above-range fee1");
  }
}
