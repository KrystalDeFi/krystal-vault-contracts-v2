// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { SharedV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedV4StrategyLib.sol";
import { SharedV4ValuationLib } from "../../contracts/shared-vault/libraries/SharedV4ValuationLib.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

uint256 constant V4_Q128 = 0x100000000000000000000000000000000;
uint160 constant V4_SQRT_PRICE_TICK0 = 79_228_162_514_264_337_593_543_950_336;

contract MockV4PoolManagerFees {
  using PoolIdLibrary for PoolKey;

  bytes32 internal globalsStartSlot;
  uint128 internal liquidity;
  uint256 internal fgInside0;
  uint256 internal fgInside1;
  uint256 internal fgInside0Last;
  uint256 internal fgInside1Last;

  constructor(
    uint128 _liquidity,
    uint256 _fgInside0,
    uint256 _fgInside1,
    uint256 _fgInside0Last,
    uint256 _fgInside1Last
  ) {
    liquidity = _liquidity;
    fgInside0 = _fgInside0;
    fgInside1 = _fgInside1;
    fgInside0Last = _fgInside0Last;
    fgInside1Last = _fgInside1Last;
  }

  function setPoolId(PoolId poolId) external {
    bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), bytes32(uint256(6))));
    globalsStartSlot = bytes32(uint256(stateSlot) + 1);
  }

  function extsload(bytes32) external pure returns (bytes32 value) {
    value = bytes32(uint256(V4_SQRT_PRICE_TICK0));
  }

  function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
    values = new bytes32[](nSlots);
    if (nSlots == 2 && startSlot == globalsStartSlot) {
      values[0] = bytes32(fgInside0);
      values[1] = bytes32(fgInside1);
    } else if (nSlots == 3) {
      values[0] = bytes32(uint256(liquidity));
      values[1] = bytes32(fgInside0Last);
      values[2] = bytes32(fgInside1Last);
    }
  }

  function extsload(bytes32[] calldata slots) external pure returns (bytes32[] memory values) {
    values = new bytes32[](slots.length);
  }
}

contract MockV4NfpmFees {
  using PoolIdLibrary for PoolKey;

  MockV4PoolManagerFees internal manager;
  address internal token0;
  address internal token1;
  uint128 internal liquidity;
  int24 internal tickLower;
  int24 internal tickUpper;

  constructor(
    MockV4PoolManagerFees _manager,
    address _token0,
    address _token1,
    uint128 _liquidity,
    int24 _tickLower,
    int24 _tickUpper
  ) {
    manager = _manager;
    token0 = _token0;
    token1 = _token1;
    liquidity = _liquidity;
    tickLower = _tickLower;
    tickUpper = _tickUpper;
    manager.setPoolId(_poolKey().toId());
  }

  function poolManager() external view returns (IPoolManager) {
    return IPoolManager(address(manager));
  }

  function getPositionLiquidity(uint256) external view returns (uint128) {
    return liquidity;
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory, PositionInfo) {
    PoolKey memory key = _poolKey();
    return (key, PositionInfoLibrary.initialize(key, tickLower, tickUpper));
  }

  function modifyLiquidities(bytes calldata, uint256) external pure {
    revert("hostile hook on fee-sync");
  }

  function _poolKey() internal view returns (PoolKey memory key) {
    key.currency0 = Currency.wrap(token0);
    key.currency1 = Currency.wrap(token1);
    key.fee = 500;
    key.tickSpacing = 60;
    key.hooks = IHooks(address(0));
  }
}

contract V4CollectHarness {
  function collect(address posm, uint256 tokenId, ICommon.FeeConfig memory fc) external {
    SharedV4StrategyLib.collectFees(posm, tokenId, fc);
  }
}

contract MockV4BalanceToken {
  mapping(address => uint256) public balanceOf;
}

contract SharedStrategyFeeAccrualV4Test is Test {
  int24 constant TICK_LOWER = -100;
  int24 constant TICK_UPPER = 100;
  uint128 constant LIQUIDITY = 1e18;
  uint256 constant FG_INSIDE0 = V4_Q128;
  uint256 constant FG_INSIDE1 = 2 * V4_Q128;

  function _setupCollect(uint256 fg0, uint256 fg1, uint256 fg0Last, uint256 fg1Last)
    internal
    returns (address nfpm, V4CollectHarness harness)
  {
    MockV4BalanceToken token0 = new MockV4BalanceToken();
    MockV4BalanceToken token1 = new MockV4BalanceToken();
    MockV4PoolManagerFees manager = new MockV4PoolManagerFees(LIQUIDITY, fg0, fg1, fg0Last, fg1Last);
    nfpm = address(new MockV4NfpmFees(manager, address(token0), address(token1), LIQUIDITY, TICK_LOWER, TICK_UPPER));
    harness = new V4CollectHarness();
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

  function test_v4_collectFees_toleratesHookRevert_whenNoUncollectedFees() public {
    (address nfpm, V4CollectHarness harness) = _setupCollect(FG_INSIDE0, FG_INSIDE1, FG_INSIDE0, FG_INSIDE1);
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }

  function test_v4_collectFees_toleratesHookRevert_whenFeeGrowthInsideBelowLast() public {
    (address nfpm, V4CollectHarness harness) = _setupCollect(FG_INSIDE0, FG_INSIDE1, FG_INSIDE0 + 1, FG_INSIDE1);
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }

  function test_v4_collectFees_toleratesHookRevert_whenPositiveFeeGrowthRoundsToZero() public {
    (address nfpm, V4CollectHarness harness) = _setupCollect(FG_INSIDE0 + 1, FG_INSIDE1, FG_INSIDE0, FG_INSIDE1);
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }

  function test_v4_getPositionAmountsSplit_matches_separate_valuations() public {
    (address nfpm,) = _setupCollect(FG_INSIDE0, FG_INSIDE1, 0, 0);

    (uint256 splitTotal0, uint256 splitTotal1, uint256 splitPrincipal0, uint256 splitPrincipal1) =
      SharedV4ValuationLib.getPositionAmountsSplit(nfpm, 1);
    (uint256 total0, uint256 total1) = SharedV4ValuationLib.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = SharedV4ValuationLib.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(splitTotal0, total0, "split total0 matches gross valuation");
    assertEq(splitTotal1, total1, "split total1 matches gross valuation");
    assertEq(splitPrincipal0, principal0, "split principal0 matches principal valuation");
    assertEq(splitPrincipal1, principal1, "split principal1 matches principal valuation");
  }

  function test_v4_collectFees_reRevertsHookRevert_whenFeesPresent() public {
    (address nfpm, V4CollectHarness harness) = _setupCollect(FG_INSIDE0, FG_INSIDE1, 0, 0);
    vm.expectRevert(bytes("hostile hook on fee-sync"));
    harness.collect(nfpm, 1, _emptyFeeConfig());
  }

  // -------------------------------------------------------------------------
  // Valuation parity with the Pancake twin suite (SharedStrategyFeeAccrualPancake.t.sol):
  // the V4 valuation math is a fork of the same fee-growth model and must mirror its tests.
  // -------------------------------------------------------------------------

  // With LIQUIDITY = 1e18: fgInside0 = Q128 -> pending0 = mulDiv(Q128, 1e18, Q128) = 1e18,
  // fgInside1 = 2*Q128 -> pending1 = 2e18.
  uint256 constant PENDING0 = 1e18;
  uint256 constant PENDING1 = 2e18;

  function test_v4_getPositionAmounts_includes_pending_fees() public {
    (address nfpm,) = _setupCollect(FG_INSIDE0, FG_INSIDE1, 0, 0);

    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = SharedV4ValuationLib.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0 + PENDING0, "amount0 = principal + pending fees");
    assertEq(amount1, principal1 + PENDING1, "amount1 = principal + pending fees");
  }

  function test_v4_getPositionPrincipalAmounts_excludes_fees() public {
    (address nfpm,) = _setupCollect(FG_INSIDE0, FG_INSIDE1, 0, 0);

    (uint256 principal0, uint256 principal1) = SharedV4ValuationLib.getPositionPrincipalAmounts(nfpm, 1);
    (uint256 total0, uint256 total1) = SharedV4ValuationLib.getPositionAmounts(nfpm, 1);

    assertGt(total0, principal0, "total exceeds principal because of pending fees");
    assertGt(total1, principal1, "total exceeds principal because of pending fees");
  }

  function test_v4_getPositionAmounts_zero_pending_when_fgInsideLast_equals_current() public {
    (address nfpm,) = _setupCollect(FG_INSIDE0, FG_INSIDE1, FG_INSIDE0, FG_INSIDE1);

    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = SharedV4ValuationLib.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0, principal0, "no pending: amount0 == principal0");
    assertEq(amount1, principal1, "no pending: amount1 == principal1");
  }

  /// @dev F7-parity: fee-growth deltas wrap by design (mirrors Uniswap accounting). With
  ///      current = Q128/2 and last = 2^256 - Q128/2, delta = Q128 (mod 2^256), so pending =
  ///      mulDiv(Q128, 1e18, Q128) = 1e18 per token. Valuation must not revert under the wrap
  ///      and must report the wrapped delta's fees — the Pancake twin pins the same case.
  function test_v4_getPositionAmounts_wraparound_fee_growth() public {
    uint256 last = type(uint256).max - (V4_Q128 / 2) + 1;
    (address nfpm,) = _setupCollect(V4_Q128 / 2, V4_Q128 / 2, last, last);

    (uint256 amount0, uint256 amount1) = SharedV4ValuationLib.getPositionAmounts(nfpm, 1);
    (uint256 principal0, uint256 principal1) = SharedV4ValuationLib.getPositionPrincipalAmounts(nfpm, 1);

    assertEq(amount0 - principal0, 1e18, "wrapped fee-growth yields the expected pending fees (token0)");
    assertEq(amount1 - principal1, 1e18, "wrapped fee-growth yields the expected pending fees (token1)");
  }
}
