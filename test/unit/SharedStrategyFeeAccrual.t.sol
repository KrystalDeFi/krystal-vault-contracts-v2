// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
uint256 constant Q128 = 0x100000000000000000000000000000000;

// sqrtPrice at tick=0: 2^96
uint160 constant SQRT_PRICE_TICK0 = 79228162514264337593543950336;

// ---------------------------------------------------------------------------
// V3 mocks
// ---------------------------------------------------------------------------

contract MockV3Pool {
  uint160 public sqrtPriceX96;
  int24 public currentTick;

  // tick data: (liquidityGross, liquidityNet, feeGrowthOutside0, feeGrowthOutside1, 0, 0, 0, false)
  mapping(int24 => uint256) public tickFg0Outside;
  mapping(int24 => uint256) public tickFg1Outside;

  uint256 public fg0Global;
  uint256 public fg1Global;

  constructor(uint160 _sqrtPrice, int24 _tick, uint256 _fg0, uint256 _fg1) {
    sqrtPriceX96 = _sqrtPrice;
    currentTick = _tick;
    fg0Global = _fg0;
    fg1Global = _fg1;
  }

  function setTickOutside(int24 tick, uint256 fg0, uint256 fg1) external {
    tickFg0Outside[tick] = fg0;
    tickFg1Outside[tick] = fg1;
  }

  // V3 slot0: (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8 feeProtocol, bool)
  function slot0() external view returns (
    uint160, int24, uint16, uint16, uint16, uint8, bool
  ) {
    return (sqrtPriceX96, currentTick, 0, 0, 0, 0, true);
  }

  // V3 ticks: (uint128 liquidityGross, int128 liquidityNet, uint256 fg0Outside, uint256 fg1Outside, int56, uint160, uint32, bool)
  function ticks(int24 tick) external view returns (
    uint128, int128, uint256 fg0, uint256 fg1, int56, uint160, uint32, bool
  ) {
    return (0, 0, tickFg0Outside[tick], tickFg1Outside[tick], 0, 0, 0, false);
  }

  function feeGrowthGlobal0X128() external view returns (uint256) { return fg0Global; }
  function feeGrowthGlobal1X128() external view returns (uint256) { return fg1Global; }
}

contract MockV3Factory {
  address public pool;
  constructor(address _pool) { pool = _pool; }
  function getPool(address, address, uint24) external view returns (address) { return pool; }
}

contract MockV3NfpmWithFees {
  address public t0;
  address public t1;
  address public factoryAddr;
  uint128 public liquidity;
  uint256 public fg0Last;
  uint256 public fg1Last;
  uint128 public owed0;
  uint128 public owed1;
  int24 public tickLower;
  int24 public tickUpper;

  constructor(
    address _factory,
    address _t0,
    address _t1,
    uint128 _liquidity,
    int24 _tickLower,
    int24 _tickUpper,
    uint256 _fg0Last,
    uint256 _fg1Last,
    uint128 _owed0,
    uint128 _owed1
  ) {
    factoryAddr = _factory;
    t0 = _t0;
    t1 = _t1;
    liquidity = _liquidity;
    tickLower = _tickLower;
    tickUpper = _tickUpper;
    fg0Last = _fg0Last;
    fg1Last = _fg1Last;
    owed0 = _owed0;
    owed1 = _owed1;
  }

  function factory() external view returns (address) { return factoryAddr; }

  function positions(uint256) external view returns (
    uint96, address, address token0, address token1, uint24 fee,
    int24 tL, int24 tU, uint128 liq,
    uint256 fg0, uint256 fg1,
    uint128 o0, uint128 o1
  ) {
    return (0, address(0), t0, t1, 3000, tickLower, tickUpper, liquidity, fg0Last, fg1Last, owed0, owed1);
  }
}

// ---------------------------------------------------------------------------
// Aerodrome mocks
// ---------------------------------------------------------------------------

contract MockAerodromePool {
  uint160 public sqrtPriceX96;
  int24 public currentTick;

  mapping(int24 => uint256) public tickFg0Outside;
  mapping(int24 => uint256) public tickFg1Outside;

  uint256 public fg0Global;
  uint256 public fg1Global;

  constructor(uint160 _sqrtPrice, int24 _tick, uint256 _fg0, uint256 _fg1) {
    sqrtPriceX96 = _sqrtPrice;
    currentTick = _tick;
    fg0Global = _fg0;
    fg1Global = _fg1;
  }

  function setTickOutside(int24 tick, uint256 fg0, uint256 fg1) external {
    tickFg0Outside[tick] = fg0;
    tickFg1Outside[tick] = fg1;
  }

  // Aerodrome slot0: (uint160, int24, uint16, uint16, uint16, bool)
  function slot0() external view returns (
    uint160, int24, uint16, uint16, uint16, bool
  ) {
    return (sqrtPriceX96, currentTick, 0, 0, 0, true);
  }

  // Aerodrome ticks: (uint128 liqGross, int128 liqNet, int128 stakedLiqNet, uint256 fg0Outside, uint256 fg1Outside, uint256, int56, uint160, uint32, bool)
  function ticks(int24 tick) external view returns (
    uint128, int128, int128, uint256 fg0, uint256 fg1, uint256, int56, uint160, uint32, bool
  ) {
    return (0, 0, 0, tickFg0Outside[tick], tickFg1Outside[tick], 0, 0, 0, 0, false);
  }

  function feeGrowthGlobal0X128() external view returns (uint256) { return fg0Global; }
  function feeGrowthGlobal1X128() external view returns (uint256) { return fg1Global; }
}

contract MockAerodromeFactory {
  address public pool;
  constructor(address _pool) { pool = _pool; }
  function getPool(address, address, int24) external view returns (address) { return pool; }
}

contract MockAerodromeNfpmWithFees {
  address public t0;
  address public t1;
  address public factoryAddr;
  uint128 public liquidity;
  uint256 public fg0Last;
  uint256 public fg1Last;
  uint128 public owed0;
  uint128 public owed1;
  int24 public tickLower;
  int24 public tickUpper;

  constructor(
    address _factory,
    address _t0,
    address _t1,
    uint128 _liquidity,
    int24 _tickLower,
    int24 _tickUpper,
    uint256 _fg0Last,
    uint256 _fg1Last,
    uint128 _owed0,
    uint128 _owed1
  ) {
    factoryAddr = _factory;
    t0 = _t0;
    t1 = _t1;
    liquidity = _liquidity;
    tickLower = _tickLower;
    tickUpper = _tickUpper;
    fg0Last = _fg0Last;
    fg1Last = _fg1Last;
    owed0 = _owed0;
    owed1 = _owed1;
  }

  function factory() external view returns (address) { return factoryAddr; }

  function positions(uint256) external view returns (
    uint96, address, address token0, address token1, int24 tickSpacing,
    int24 tL, int24 tU, uint128 liq,
    uint256 fg0, uint256 fg1,
    uint128 o0, uint128 o1
  ) {
    return (0, address(0), t0, t1, 60, tickLower, tickUpper, liquidity, fg0Last, fg1Last, owed0, owed1);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
contract SharedStrategyFeeAccrualTest is Test {
  // Scenario: position in range [tickLower=-100, tickUpper=100], currentTick=0.
  // All feeGrowthOutside = 0 so feeGrowthInside = feeGrowthGlobal.
  // feeGrowthInsideLast = 0 → full global is the pending delta.
  // pendingFee0 = mulDiv(fg0Global, liquidity, Q128)
  // pendingFee1 = mulDiv(fg1Global, liquidity, Q128)

  int24 constant TICK_LOWER = -100;
  int24 constant TICK_UPPER = 100;
  int24 constant CURRENT_TICK = 0;
  uint128 constant LIQUIDITY = 1e18;
  uint256 constant FG0_GLOBAL = Q128;       // 1 fee token per unit liq for token0
  uint256 constant FG1_GLOBAL = 2 * Q128;   // 2 fee tokens per unit liq for token1
  uint128 constant STORED_OWED0 = 5e18;
  uint128 constant STORED_OWED1 = 3e18;
  // pending0 = mulDiv(Q128, 1e18, Q128) = 1e18
  // pending1 = mulDiv(2*Q128, 1e18, Q128) = 2e18
  uint256 constant PENDING0 = 1e18;
  uint256 constant PENDING1 = 2e18;

  // ---------------------------------------------------------------------------
  // SharedV3Strategy
  // ---------------------------------------------------------------------------

  function _setupV3() internal returns (SharedV3Strategy strategy, address nfpm) {
    MockV3Pool pool = new MockV3Pool(SQRT_PRICE_TICK0, CURRENT_TICK, FG0_GLOBAL, FG1_GLOBAL);
    // feeGrowthOutside = 0 at both ticks (already zero by default) → feeGrowthInside = global

    MockV3Factory factory = new MockV3Factory(address(pool));

    nfpm = address(new MockV3NfpmWithFees(
      address(factory),
      address(0x1111),   // token0
      address(0x2222),   // token1
      LIQUIDITY,
      TICK_LOWER,
      TICK_UPPER,
      0,                 // feeGrowthInside0LastX128
      0,                 // feeGrowthInside1LastX128
      STORED_OWED0,
      STORED_OWED1
    ));

    strategy = new SharedV3Strategy(address(1), address(1));
  }

  function test_v3_getPositionAmounts_includes_pending_fees() public {
    (SharedV3Strategy strategy, address nfpm) = _setupV3();

    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);

    // fees portion = stored + pending
    uint256 expectedFees0 = STORED_OWED0 + PENDING0;
    uint256 expectedFees1 = STORED_OWED1 + PENDING1;

    // principal is non-zero (position in range at 1:1 price); we check fee component
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0 + expectedFees0, "amount0 should be principal + stored + pending fees");
    assertEq(amount1, principal1 + expectedFees1, "amount1 should be principal + stored + pending fees");
  }

  function test_v3_getPositionPrincipalAmounts_excludes_fees() public {
    (SharedV3Strategy strategy, address nfpm) = _setupV3();

    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);
    (uint256 total0, uint256 total1) = strategy.getPositionAmounts(nfpm, 1);

    assertGt(total0, principal0, "total should exceed principal because of fees");
    assertGt(total1, principal1, "total should exceed principal because of fees");
  }

  function test_v3_getPositionAmounts_zero_pending_when_fgInsideLast_equals_current() public {
    // When feeGrowthInsideLast == current feeGrowthInside, no new fees have accrued.
    MockV3Pool pool = new MockV3Pool(SQRT_PRICE_TICK0, CURRENT_TICK, FG0_GLOBAL, FG1_GLOBAL);
    MockV3Factory factory = new MockV3Factory(address(pool));

    // Set fgLast == global (fgInside == global since outside=0), so delta = 0
    address nfpm = address(new MockV3NfpmWithFees(
      address(factory),
      address(0x1111),
      address(0x2222),
      LIQUIDITY,
      TICK_LOWER,
      TICK_UPPER,
      FG0_GLOBAL,  // feeGrowthInside0LastX128 == current inside → delta = 0
      FG1_GLOBAL,
      STORED_OWED0,
      STORED_OWED1
    ));

    SharedV3Strategy strategy = new SharedV3Strategy(address(1), address(1));
    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0 + STORED_OWED0, "pending=0, only stored owed");
    assertEq(amount1, principal1 + STORED_OWED1, "pending=0, only stored owed");
  }

  function test_v3_getPositionAmounts_out_of_range_no_new_pending() public {
    // Position above current tick: currentTick < tickLower → no new fees accruing.
    // fgInside = 0 when out of range (above), stored owed is still returned.
    int24 tLow = 200;
    int24 tHigh = 400;
    int24 curTick = 0; // below range
    uint160 sqrtPrice = SQRT_PRICE_TICK0;

    MockV3Pool pool = new MockV3Pool(sqrtPrice, curTick, FG0_GLOBAL, FG1_GLOBAL);
    // For tick >= curTick (tickLower=200 > curTick=0):
    //   fgBelow = fgGlobal - lowerFgOutside; with lowerFgOutside=0 → fgBelow = fgGlobal
    //   fgAbove = upperFgOutside = 0
    //   fgInside = fgGlobal - fgGlobal - 0 = 0
    // delta = 0 - fgInsideLast; with fgInsideLast=0 → delta = 0 (unchecked wraps but mulDiv with 0 liq = 0)
    // Actually, fgInsideLast=0 and fgInside=0 → delta=0 → pending=0
    MockV3Factory factory = new MockV3Factory(address(pool));

    address nfpm = address(new MockV3NfpmWithFees(
      address(factory),
      address(0x1111),
      address(0x2222),
      1e18,
      tLow,
      tHigh,
      0,           // fgInsideLast=0
      0,
      STORED_OWED0,
      STORED_OWED1
    ));

    SharedV3Strategy strategy = new SharedV3Strategy(address(1), address(1));
    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    // Out of range: principal for the in-range token is non-zero, but no NEW pending fees
    assertEq(amount0, principal0 + STORED_OWED0, "out-of-range: only stored owed0, no new pending");
    assertEq(amount1, principal1 + STORED_OWED1, "out-of-range: only stored owed1, no new pending");
  }

  // ---------------------------------------------------------------------------
  // SharedAerodromeStrategy
  // ---------------------------------------------------------------------------

  function _setupAerodrome() internal returns (SharedAerodromeStrategy strategy, address nfpm) {
    MockAerodromePool pool = new MockAerodromePool(SQRT_PRICE_TICK0, CURRENT_TICK, FG0_GLOBAL, FG1_GLOBAL);
    MockAerodromeFactory factory = new MockAerodromeFactory(address(pool));

    nfpm = address(new MockAerodromeNfpmWithFees(
      address(factory),
      address(0x1111),
      address(0x2222),
      LIQUIDITY,
      TICK_LOWER,
      TICK_UPPER,
      0,
      0,
      STORED_OWED0,
      STORED_OWED1
    ));

    strategy = new SharedAerodromeStrategy(address(1), address(1));
  }

  function test_aerodrome_getPositionAmounts_includes_pending_fees() public {
    (SharedAerodromeStrategy strategy, address nfpm) = _setupAerodrome();

    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0 + STORED_OWED0 + PENDING0, "Aerodrome: amount0 includes pending fees");
    assertEq(amount1, principal1 + STORED_OWED1 + PENDING1, "Aerodrome: amount1 includes pending fees");
  }

  function test_aerodrome_getPositionPrincipalAmounts_excludes_fees() public {
    (SharedAerodromeStrategy strategy, address nfpm) = _setupAerodrome();

    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);
    (uint256 total0, uint256 total1) = strategy.getPositionAmounts(nfpm, 1);

    assertGt(total0, principal0, "Aerodrome: total should exceed principal because of fees");
    assertGt(total1, principal1, "Aerodrome: total should exceed principal because of fees");
  }

  function test_aerodrome_getPositionAmounts_zero_pending_when_fgInsideLast_equals_current() public {
    MockAerodromePool pool = new MockAerodromePool(SQRT_PRICE_TICK0, CURRENT_TICK, FG0_GLOBAL, FG1_GLOBAL);
    MockAerodromeFactory factory = new MockAerodromeFactory(address(pool));

    address nfpm = address(new MockAerodromeNfpmWithFees(
      address(factory),
      address(0x1111),
      address(0x2222),
      LIQUIDITY,
      TICK_LOWER,
      TICK_UPPER,
      FG0_GLOBAL,
      FG1_GLOBAL,
      STORED_OWED0,
      STORED_OWED1
    ));

    SharedAerodromeStrategy strategy = new SharedAerodromeStrategy(address(1), address(1));
    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0 + STORED_OWED0, "Aerodrome pending=0, only stored owed");
    assertEq(amount1, principal1 + STORED_OWED1, "Aerodrome pending=0, only stored owed");
  }
}
