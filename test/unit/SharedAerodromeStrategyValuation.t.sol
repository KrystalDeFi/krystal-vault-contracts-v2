// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";

/// @title Live-liquidity valuation coverage for SharedAerodromeStrategy.getPositionAmounts (MED-1)
/// @notice Aerodrome twin of SharedV3StrategyValuationTest. The fee-growth-inside LOGIC is identical to
///         the V3 strategy; only the on-chain read shapes differ and must be mocked accordingly:
///           - `positions()` carries `int24 tickSpacing` at index 4 (not `uint24 fee`).
///           - `slot0()` is a typed 6-tuple call `(uint160, int24, uint16, uint16, uint16, bool)`.
///           - `ticks()` is a 10-tuple with feeGrowthOutside0/1X128 at indices 3 and 4.
///           - the pool is resolved via `ICLFactory.getPool(address,address,int24 tickSpacing)`.
///         Same non-tautology discipline: principal vs the canonical `LiquidityAmounts` library, fees
///         vs hand-derived `k·Q128` closed forms (liquidity == 1e18 ⇒ `k·Q128` of growth == `k ether`).
contract SharedAerodromeStrategyValuationTest is Test {
  uint256 internal constant Q128 = 0x100000000000000000000000000000000; // 2**128

  SharedAerodromeStrategy internal strategy;

  address internal constant NFPM = address(0x4001);
  address internal constant FACTORY = address(0x4002);
  address internal constant POOL = address(0x4003);
  address internal constant TOKEN0 = address(0x7000);
  address internal constant TOKEN1 = address(0x7001);
  int24 internal constant TICK_SPACING = 200;
  uint256 internal constant TOKEN_ID = 42;

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
    strategy = new SharedAerodromeStrategy(address(0x9001));
  }

  function _mockPosition(PosCfg memory c) internal {
    uint160 sqrtP = TickMath.getSqrtRatioAtTick(c.tickCurrent);

    // positions(): index 4 is int24 tickSpacing for Aerodrome.
    vm.mockCall(
      NFPM,
      abi.encodeWithSignature("positions(uint256)", TOKEN_ID),
      abi.encode(
        uint96(0),
        address(0),
        TOKEN0,
        TOKEN1,
        TICK_SPACING,
        c.tickLower,
        c.tickUpper,
        L,
        c.fg0Last,
        c.fg1Last,
        c.owed0,
        c.owed1
      )
    );
    vm.mockCall(NFPM, abi.encodeWithSignature("factory()"), abi.encode(FACTORY));
    vm.mockCall(
      FACTORY,
      abi.encodeWithSignature("getPool(address,address,int24)", TOKEN0, TOKEN1, TICK_SPACING),
      abi.encode(POOL)
    );
    // ICLPool.slot0() typed 6-tuple call (decoded by the strategy, so arity must match exactly).
    vm.mockCall(
      POOL, abi.encodeWithSignature("slot0()"), abi.encode(uint160(sqrtP), c.tickCurrent, uint16(0), uint16(0), uint16(0), false)
    );
    vm.mockCall(POOL, abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(c.fg0Global));
    vm.mockCall(POOL, abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(c.fg1Global));
    // ICLPool.ticks() 10-tuple: feeGrowthOutside0/1X128 at indices 3,4.
    vm.mockCall(
      POOL,
      abi.encodeWithSignature("ticks(int24)", c.tickLower),
      abi.encode(
        uint128(0), int128(0), int128(0), c.lowerOut0, c.lowerOut1, uint256(0), int56(0), uint160(0), uint32(0), false
      )
    );
    vm.mockCall(
      POOL,
      abi.encodeWithSignature("ticks(int24)", c.tickUpper),
      abi.encode(
        uint128(0), int128(0), int128(0), c.upperOut0, c.upperOut1, uint256(0), int56(0), uint160(0), uint32(0), false
      )
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

  function test_getPositionAmounts_inRange_pinsPrincipalAndFees() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: 0,
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

    assertEq(principal0, expP0, "principal0 matches canonical LiquidityAmounts");
    assertEq(principal1, expP1, "principal1 matches canonical LiquidityAmounts");
    assertEq(total0 - principal0, 3 ether, "fee0 == feeGrowthGlobal0 * L / Q128");
    assertEq(total1 - principal1, 4 ether, "fee1 == feeGrowthGlobal1 * L / Q128");

    (uint256 amt0, uint256 amt1) = strategy.getPositionAmounts(NFPM, TOKEN_ID);
    assertEq(amt0, total0, "getPositionAmounts.amount0 == split total0");
    assertEq(amt1, total1, "getPositionAmounts.amount1 == split total1");
  }

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
      fg0Last: 1 * Q128,
      fg1Last: 2 * Q128,
      owed0: 0.5 ether,
      owed1: 0.25 ether
    });
    _mockPosition(c);

    (uint256 expP0, uint256 expP1) = _expectedPrincipal(c);
    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(NFPM, TOKEN_ID);

    assertEq(principal0, expP0, "principal0");
    assertEq(principal1, expP1, "principal1");
    assertEq(total0 - principal0, 0.5 ether + 2 ether, "fee0 = owed0 + delta0");
    assertEq(total1 - principal1, 0.25 ether + 3 ether, "fee1 = owed1 + delta1");
  }

  function test_getPositionAmounts_belowRange_feeGrowthBranch() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: -1200,
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
    assertEq(total0 - principal0, 3 ether, "below-range fee0");
    assertEq(total1 - principal1, 5 ether, "below-range fee1");
  }

  function test_getPositionAmounts_aboveRange_feeGrowthBranch() public {
    PosCfg memory c = PosCfg({
      tickLower: -600,
      tickUpper: 600,
      tickCurrent: 1200,
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
    assertEq(total0 - principal0, 3 ether, "above-range fee0");
    assertEq(total1 - principal1, 6 ether, "above-range fee1");
  }
}
