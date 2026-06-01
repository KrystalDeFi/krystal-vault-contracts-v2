// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";
import { SharedPancakeV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedPancakeV4StrategyLib.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { IHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import { CLPositionInfo } from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
uint256 constant Q128 = 0x100000000000000000000000000000000;
// sqrtPrice at tick 0: 2^96
uint160 constant SQRT_PRICE_TICK0 = 79_228_162_514_264_337_593_543_950_336;

/// @dev Packs ticks the way CLPositionInfoLibrary reads them back: tickLower at bit offset 8,
///      tickUpper at bit offset 32. The int24->uint24 cast preserves the 24-bit two's-complement
///      pattern that `signextend(2, ...)` restores, so negative ticks round-trip correctly.
function packPositionInfo(int24 tickLower, int24 tickUpper) pure returns (CLPositionInfo) {
  uint256 raw = (uint256(uint24(tickUpper)) << 32) | (uint256(uint24(tickLower)) << 8);
  return CLPositionInfo.wrap(raw);
}

// ---------------------------------------------------------------------------
// Pancake CL pool manager mock — exposes the global fee growth + per-tick `feeGrowthOutside`
// snapshots that SharedPancakeV4StrategyLib reconstructs fee-growth-inside from. PancakeSwap
// Infinity's real CL PoolManager has NO `getFeeGrowthInside` getter, so the strategy derives it
// via `[global - below - above]`. With both boundary ticks' `feeGrowthOutside` set to zero and the
// current tick inside the range, the reconstruction collapses to `feeGrowthInside == global`, so we
// seed the globals with the desired inside values.
// ---------------------------------------------------------------------------
contract MockPancakeCLPoolManagerFees {
  uint160 internal sqrtPriceX96;
  int24 internal currentTick;
  uint256 internal fgInside0;
  uint256 internal fgInside1;

  constructor(uint160 _sqrtPrice, int24 _tick, uint256 _fgInside0, uint256 _fgInside1) {
    sqrtPriceX96 = _sqrtPrice;
    currentTick = _tick;
    fgInside0 = _fgInside0;
    fgInside1 = _fgInside1;
  }

  function getSlot0(bytes32) external view returns (uint160, int24, uint24, uint24) {
    return (sqrtPriceX96, currentTick, 0, 0);
  }

  // Boundary ticks carry zero `feeGrowthOutside`; with the current tick within [tickLower, tickUpper]
  // the reconstruction yields `feeGrowthInside == feeGrowthGlobal`, so the globals below ARE the
  // intended inside values for these tests.
  function getFeeGrowthGlobals(bytes32) external view returns (uint256, uint256) {
    return (fgInside0, fgInside1);
  }

  function getPoolTickInfo(bytes32, int24) external pure returns (uint128, int128, uint256, uint256) {
    return (0, 0, 0, 0);
  }
}

// ---------------------------------------------------------------------------
// Pancake position manager mock
// ---------------------------------------------------------------------------
contract MockPancakeNfpmFees {
  address public clPoolManager;
  address public permit2;
  address internal token0;
  address internal token1;
  uint128 internal liquidity;
  int24 internal tickLower;
  int24 internal tickUpper;
  uint256 internal fgInside0Last;
  uint256 internal fgInside1Last;

  constructor(
    address _clPoolManager,
    address _token0,
    address _token1,
    uint128 _liquidity,
    int24 _tickLower,
    int24 _tickUpper,
    uint256 _fgInside0Last,
    uint256 _fgInside1Last
  ) {
    clPoolManager = _clPoolManager;
    permit2 = address(0x1234);
    token0 = _token0;
    token1 = _token1;
    liquidity = _liquidity;
    tickLower = _tickLower;
    tickUpper = _tickUpper;
    fgInside0Last = _fgInside0Last;
    fgInside1Last = _fgInside1Last;
  }

  function _poolKey() internal view returns (PoolKey memory key) {
    key.currency0 = Currency.wrap(token0);
    key.currency1 = Currency.wrap(token1);
    key.hooks = IHooks(address(0));
    key.poolManager = IPoolManager(clPoolManager);
    key.fee = 500;
    key.parameters = bytes32(0);
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory, CLPositionInfo) {
    return (_poolKey(), packPositionInfo(tickLower, tickUpper));
  }

  function getPositionLiquidity(uint256) external view returns (uint128) {
    return liquidity;
  }

  function positions(
    uint256
  ) external view returns (PoolKey memory, int24, int24, uint128, uint256, uint256, address) {
    return (_poolKey(), tickLower, tickUpper, liquidity, fgInside0Last, fgInside1Last, address(0));
  }

  /// @dev Simulates a fragile/hostile pool whose remove-liquidity hook reverts on the zero-liquidity
  ///      fee-sync `collectFees` performs. The strategy must NOT reach this when the position has no
  ///      uncollected fees (it short-circuits first).
  function modifyLiquidities(bytes calldata, uint256) external pure {
    revert("hostile hook on fee-sync");
  }
}

/// @dev Drives the lib's external `collectFees(posm, tokenId, fc)` (a delegatecall into the lib, so
///      `address(this)` is this harness — mirroring a strategy delegatecalled by the vault).
contract PancakeCollectHarness {
  function collect(address posm, uint256 tokenId, ICommon.FeeConfig memory fc) external {
    SharedPancakeV4StrategyLib.collectFees(posm, tokenId, fc);
  }
}

// ---------------------------------------------------------------------------
// Tests — Pancake getPositionAmounts fee accrual (F1)
// ---------------------------------------------------------------------------
contract SharedStrategyFeeAccrualPancakeTest is Test {
  int24 constant TICK_LOWER = -100;
  int24 constant TICK_UPPER = 100;
  int24 constant CURRENT_TICK = 0;
  uint128 constant LIQUIDITY = 1e18;
  // fgInside0 = Q128 -> pending0 = mulDiv(Q128, 1e18, Q128) = 1e18
  // fgInside1 = 2*Q128 -> pending1 = 2e18
  uint256 constant FG_INSIDE0 = Q128;
  uint256 constant FG_INSIDE1 = 2 * Q128;
  uint256 constant PENDING0 = 1e18;
  uint256 constant PENDING1 = 2e18;

  address constant TOKEN0 = address(0x1111);
  address constant TOKEN1 = address(0x2222);

  function _setup(
    uint256 fg0,
    uint256 fg1,
    uint256 fg0Last,
    uint256 fg1Last
  ) internal returns (SharedPancakeV4Strategy strategy, address nfpm) {
    MockPancakeCLPoolManagerFees manager = new MockPancakeCLPoolManagerFees(SQRT_PRICE_TICK0, CURRENT_TICK, fg0, fg1);
    nfpm = address(
      new MockPancakeNfpmFees(address(manager), TOKEN0, TOKEN1, LIQUIDITY, TICK_LOWER, TICK_UPPER, fg0Last, fg1Last)
    );
    strategy = new SharedPancakeV4Strategy(address(0xBEEF));
  }

  function test_pancake_getPositionAmounts_includes_pending_fees() public {
    (SharedPancakeV4Strategy strategy, address nfpm) = _setup(FG_INSIDE0, FG_INSIDE1, 0, 0);

    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0 + PENDING0, "amount0 = principal + pending fees (native getFeeGrowthInside)");
    assertEq(amount1, principal1 + PENDING1, "amount1 = principal + pending fees (native getFeeGrowthInside)");
  }

  function test_pancake_getPositionPrincipalAmounts_excludes_fees() public {
    (SharedPancakeV4Strategy strategy, address nfpm) = _setup(FG_INSIDE0, FG_INSIDE1, 0, 0);

    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);
    (uint256 total0, uint256 total1) = strategy.getPositionAmounts(nfpm, 1);

    assertGt(total0, principal0, "total exceeds principal because of pending fees");
    assertGt(total1, principal1, "total exceeds principal because of pending fees");
  }

  function test_pancake_getPositionAmounts_zero_pending_when_fgInsideLast_equals_current() public {
    // When the position's stored feeGrowthInsideLast equals the current inside growth, delta = 0.
    (SharedPancakeV4Strategy strategy, address nfpm) = _setup(FG_INSIDE0, FG_INSIDE1, FG_INSIDE0, FG_INSIDE1);

    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0, "no pending: amount0 == principal0");
    assertEq(amount1, principal1, "no pending: amount1 == principal1");
  }

  function test_pancake_getPositionAmounts_wraparound_fee_growth() public {
    // Fee-growth is intentionally unchecked (wraps). With current = Q128/2 and last = 2^256 - Q128/2,
    // delta = current - last (mod 2^256) = Q128, so pending = mulDiv(Q128, 1e18, Q128) = 1e18 for BOTH
    // tokens. Valuation must not revert and must report the wrapped delta's fees.
    uint256 last = type(uint256).max - (Q128 / 2) + 1;
    (SharedPancakeV4Strategy strategy, address nfpm) = _setup(Q128 / 2, Q128 / 2, last, last);

    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0 - principal0, 1e18, "wrapped fee-growth yields the expected pending fees (token0)");
    assertEq(amount1 - principal1, 1e18, "wrapped fee-growth yields the expected pending fees (token1)");
  }

  function _emptyFeeConfig() internal pure returns (ICommon.FeeConfig memory fc) {
    fc = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });
  }

  /// @dev Sets up a NFPM whose fee-sync collect (modifyLiquidities) reverts (hostile hook), with real
  ///      balanceOf-capable tokens so the pre-collect balance snapshot works. fg0Last/fg1Last control the
  ///      view-reported uncollected fees that collectFees() consults in the catch branch.
  function _setupCollect(
    uint256 fg0,
    uint256 fg1,
    uint256 fg0Last,
    uint256 fg1Last
  ) internal returns (address nfpm, PancakeCollectHarness harness) {
    MockBalanceToken token0 = new MockBalanceToken();
    MockBalanceToken token1 = new MockBalanceToken();
    MockPancakeCLPoolManagerFees manager = new MockPancakeCLPoolManagerFees(SQRT_PRICE_TICK0, CURRENT_TICK, fg0, fg1);
    nfpm = address(
      new MockPancakeNfpmFees(
        address(manager), address(token0), address(token1), LIQUIDITY, TICK_LOWER, TICK_UPPER, fg0Last, fg1Last
      )
    );
    harness = new PancakeCollectHarness();
  }

  /// @dev M3 (strategy-level): when the position has NO uncollected fees, a failing fee-sync collect (a pool
  ///      hook reverting on the zero-liquidity DECREASE+TAKE) is TOLERATED — collectFees does not revert, so
  ///      such a position cannot brick SharedVault.withdraw. fgInsideLast == current inside growth => zero fees.
  function test_pancake_collectFees_toleratesHookRevert_whenNoUncollectedFees() public {
    (address nfpm, PancakeCollectHarness harness) = _setupCollect(FG_INSIDE0, FG_INSIDE1, FG_INSIDE0, FG_INSIDE1);
    harness.collect(nfpm, 1, _emptyFeeConfig()); // must NOT revert (zero pending fees -> swallow the hook revert)
  }

  /// @dev The failed-collect fallback must not interpret a fee-growth-inside value below the stored
  ///      last value as a huge unchecked wrapped delta. Such a read is not reliable evidence that fees
  ///      are collectable, so a hostile hook should still be tolerated in the zero-positive-fee path.
  function test_pancake_collectFees_toleratesHookRevert_whenFeeGrowthInsideBelowLast() public {
    (address nfpm, PancakeCollectHarness harness) =
      _setupCollect(FG_INSIDE0, FG_INSIDE1, FG_INSIDE0 + 1, FG_INSIDE1);
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }

  function test_pancake_collectFees_toleratesHookRevert_whenPositiveFeeGrowthRoundsToZero() public {
    (address nfpm, PancakeCollectHarness harness) =
      _setupCollect(FG_INSIDE0 + 1, FG_INSIDE1, FG_INSIDE0, FG_INSIDE1);
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }

  /// @dev Conversely, when the position HAS uncollected fees, a failing fee-sync collect is re-reverted with
  ///      the original reason — proving the tolerate path is conditional on zero fees and the fee-fairness
  ///      guarantee is preserved (withdraw still reverts when collectable fees can't be settled).
  function test_pancake_collectFees_reRevertsHookRevert_whenFeesPresent() public {
    (address nfpm, PancakeCollectHarness harness) = _setupCollect(FG_INSIDE0, FG_INSIDE1, 0, 0); // delta > 0
    vm.expectRevert(bytes("hostile hook on fee-sync"));
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }
}

/// @dev Minimal balanceOf-capable token for the collectFees pre-collect snapshot (no transfers occur in the
///      tests because the fee-sync collect reverts before any settlement).
contract MockBalanceToken {
  mapping(address => uint256) public balanceOf;
}
