// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SharedStrategyFees } from "../../contracts/shared-vault/libraries/SharedStrategyFees.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IFeeTaker } from "../../contracts/public-vault/interfaces/strategies/IFeeTaker.sol";

/// @dev Minimal ERC20 sufficient for SafeERC20.safeTransfer.
contract FeesMockToken {
  mapping(address => uint256) public balanceOf;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

/// @dev Exposes the internal `SharedStrategyFees.applyFees` and holds the tokens being charged so
///      `address(this)` (the fee payer) is this harness — mirroring how a strategy delegatecalled by the
///      vault becomes the fee payer in production.
contract FeesHarness {
  function applyFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    ICommon.FeeConfig memory fc
  ) external returns (uint256 fee0, uint256 fee1) {
    return SharedStrategyFees.applyFees(token0, amount0, token1, amount1, fc);
  }
}

/// @notice Direct unit tests for the canonical shared fee model used by all four shared-vault strategies
///         (V3, Aerodrome, V4, PancakeV4) after the LpFeeTaker removal. Covers distribution, ordering,
///         the sequential >100% clamp, and the zero/address(0) edge cases.
contract SharedStrategyFeesTest is Test {
  uint256 internal constant Q64 = 0x10000000000000000;

  FeesHarness internal harness;
  FeesMockToken internal t0;
  FeesMockToken internal t1;

  address internal platform = address(0xAA01);
  address internal owner = address(0xAA02);
  address internal gasRecipient = address(0xAA03);

  function setUp() public {
    harness = new FeesHarness();
    t0 = new FeesMockToken();
    t1 = new FeesMockToken();
    t0.mint(address(harness), 1_000_000 ether);
    t1.mint(address(harness), 1_000_000 ether);
  }

  function _config(
    uint16 platformBps,
    uint16 ownerBps,
    uint64 gasFeeX64
  ) internal view returns (ICommon.FeeConfig memory fc) {
    fc = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: ownerBps,
      vaultOwner: owner,
      platformFeeBasisPoint: platformBps,
      platformFeeRecipient: platform,
      gasFeeX64: gasFeeX64,
      gasFeeRecipient: gasRecipient
    });
  }

  /// @dev Normal case: platform 10% + owner 5% + gas 25% = 40% total, all under 100%. Each recipient gets
  ///      its exact slice of BOTH tokens (no consolidation), and events are emitted from the payer in order
  ///      platform(t0,t1) → owner(t0,t1) → gas(t0,t1).
  function test_applyFees_distributesEachTokenSliceDirectly() public {
    uint256 a0 = 1_000;
    uint256 a1 = 2_000;
    uint64 gas25 = uint64(Q64 / 4); // 25%

    vm.expectEmit(true, true, true, true, address(harness));
    emit IFeeTaker.FeeCollected(address(harness), IFeeTaker.FeeType.PLATFORM, platform, address(t0), 100);
    vm.expectEmit(true, true, true, true, address(harness));
    emit IFeeTaker.FeeCollected(address(harness), IFeeTaker.FeeType.PLATFORM, platform, address(t1), 200);
    vm.expectEmit(true, true, true, true, address(harness));
    emit IFeeTaker.FeeCollected(address(harness), IFeeTaker.FeeType.OWNER, owner, address(t0), 50);
    vm.expectEmit(true, true, true, true, address(harness));
    emit IFeeTaker.FeeCollected(address(harness), IFeeTaker.FeeType.OWNER, owner, address(t1), 100);
    vm.expectEmit(true, true, true, true, address(harness));
    emit IFeeTaker.FeeCollected(address(harness), IFeeTaker.FeeType.GAS, gasRecipient, address(t0), 250);
    vm.expectEmit(true, true, true, true, address(harness));
    emit IFeeTaker.FeeCollected(address(harness), IFeeTaker.FeeType.GAS, gasRecipient, address(t1), 500);

    (uint256 fee0, uint256 fee1) = harness.applyFees(address(t0), a0, address(t1), a1, _config(1_000, 500, gas25));

    assertEq(fee0, 400, "fee0 = 40% of 1000");
    assertEq(fee1, 800, "fee1 = 40% of 2000");
    assertEq(t0.balanceOf(platform), 100);
    assertEq(t1.balanceOf(platform), 200);
    assertEq(t0.balanceOf(owner), 50);
    assertEq(t1.balanceOf(owner), 100);
    assertEq(t0.balanceOf(gasRecipient), 250);
    assertEq(t1.balanceOf(gasRecipient), 500);
  }

  /// @dev Sequential clamp: platform 10% + owner 5% + gas 90% would be 105%. Each fee is computed from the
  ///      ORIGINAL amount and clamped to the running remainder, so gas absorbs only the remaining 85% and the
  ///      total fee is exactly 100% (never more) — no revert, no underflow.
  function test_applyFees_clampsGasToRemainderWhenOver100pct() public {
    uint256 a0 = 1_000;
    uint256 a1 = 2_000;
    uint64 gas90 = uint64((9 * Q64) / 10); // 90%

    (uint256 fee0, uint256 fee1) = harness.applyFees(address(t0), a0, address(t1), a1, _config(1_000, 500, gas90));

    assertEq(fee0, a0, "fee0 clamped to 100% of amount0");
    assertEq(fee1, a1, "fee1 clamped to 100% of amount1");
    // platform 100 + owner 50 + gas 850 (req 900) == 1000; platform 200 + owner 100 + gas 1700 (req 1800) == 2000
    assertEq(t0.balanceOf(gasRecipient), 850, "gas t0 clamped to remainder");
    assertEq(t1.balanceOf(gasRecipient), 1_700, "gas t1 clamped to remainder");
    assertEq(t0.balanceOf(platform) + t0.balanceOf(owner) + t0.balanceOf(gasRecipient), a0, "total t0 == collected");
    assertEq(t1.balanceOf(platform) + t1.balanceOf(owner) + t1.balanceOf(gasRecipient), a1, "total t1 == collected");
  }

  /// @dev A single gas fee at the uint64 max is `(2^64-1)/2^64 ≈ 99.999%` of the amount, so for 1_000 it
  ///      floors to 999 — strictly LESS than the collected amount. This proves the gas fee can never exceed
  ///      what was collected even at the maximum representable gasFeeX64, so `collected - fee` cannot underflow.
  function test_applyFees_maxGasFeeNeverExceedsAmount() public {
    (uint256 fee0, uint256 fee1) = harness.applyFees(address(t0), 1_000, address(t1), 0, _config(0, 0, type(uint64).max));
    assertEq(fee0, 999, "max gasFeeX64 ~= 99.999% of 1000 -> 999 (< amount)");
    assertLt(fee0, 1_000, "fee can never reach the full amount from gasFeeX64 alone");
    assertEq(fee1, 0, "no amount1");
    assertEq(t0.balanceOf(gasRecipient), 999);
  }

  /// @dev address(0) recipients (or zero bps) skip that fee type entirely.
  function test_applyFees_skipsZeroRecipientAndZeroBps() public {
    ICommon.FeeConfig memory fc = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 500,
      vaultOwner: address(0), // owner fee skipped despite nonzero bps
      platformFeeBasisPoint: 0, // platform fee skipped (zero bps)
      platformFeeRecipient: platform,
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });
    (uint256 fee0, uint256 fee1) = harness.applyFees(address(t0), 1_000, address(t1), 2_000, fc);
    assertEq(fee0, 0, "no fee taken");
    assertEq(fee1, 0, "no fee taken");
    assertEq(t0.balanceOf(platform), 0);
    assertEq(t0.balanceOf(owner), 0);
  }

  /// @dev Zero amounts take no fee and emit nothing.
  function test_applyFees_zeroAmounts() public {
    (uint256 fee0, uint256 fee1) = harness.applyFees(address(t0), 0, address(t1), 0, _config(1_000, 500, uint64(Q64 / 4)));
    assertEq(fee0, 0);
    assertEq(fee1, 0);
  }
}
