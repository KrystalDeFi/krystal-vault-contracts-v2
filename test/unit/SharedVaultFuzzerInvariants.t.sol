// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { SharedVaultFuzzer } from "../echidna-fuzzer/Fuzzer.sharedVault.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";

/// @title Deterministic driver for the Echidna mock harness's new invariants (MED-2 / LOW)
/// @notice The aggregate-solvency invariant (`_assertSolvent`, wired into every `_assert*ShareConservation`)
///         and the off-ratio no-dilution handler (`multi_offRatio_deposit_neverDilutes`) were added to
///         `Fuzzer.sharedVault.sol`. The full Echidna campaign can't run in this environment due to a
///         crytic-compile / Foundry build-info version mismatch (independent of these changes), so this
///         forge driver provides the offline, CI-runnable verification:
///           1. It deploys the real harness and drives an interleaved deposit/withdraw/off-ratio sequence
///              across all vaults. Every handler runs the conservation + solvency asserts internally, so a
///              clean run proves the new invariants do NOT false-positive on real state transitions.
///           2. It independently recomputes the solvency margin and asserts it is TIGHT (the sum of all
///              holders' previewWithdraw is within a few wei of total balances), proving the `<= totals`
///              bound actually constrains the system rather than passing vacuously.
contract SharedVaultFuzzerInvariantsTest is Test {
  SharedVaultFuzzer internal fuzzer;

  function setUp() public {
    // The harness constructor seeds a native-ETH/WETH vault, so it needs an ETH balance during
    // construction — Echidna supplies this via `balanceContract: 1e24` in config.yaml. Pre-fund the
    // harness's CREATE address with the same balance so construction succeeds under forge.
    address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
    vm.deal(predicted, 1_000_000 ether);
    fuzzer = new SharedVaultFuzzer();
    assertEq(address(fuzzer), predicted, "create address prediction");
  }

  /// @notice Drive a mixed sequence. A revert here = an invariant (conservation or solvency) was violated.
  function test_invariants_hold_under_mixed_sequence() public {
    // idle vault (2 tokens): several depositors, then partial/full withdrawals.
    fuzzer.idle_deposit(0, 5e18, 5e18);
    fuzzer.idle_deposit(1, 3e18, 3e18);
    fuzzer.idle_deposit(2, 1e18, 1e18);
    fuzzer.idle_withdraw(0, 12_345);
    fuzzer.idle_withdraw(1, 999_999);

    // multi vault (4 tokens, mixed decimals): on-ratio deposits, off-ratio baskets, withdrawal.
    fuzzer.multi_deposit(0, 2e18);
    fuzzer.multi_deposit(1, 1e18);
    fuzzer.multi_offRatio_deposit_neverDilutes(0, 7e18, 1e17, 3e8, 9e9);
    fuzzer.multi_offRatio_deposit_neverDilutes(1, 1e18, 5e20, 1e6, 1e10);
    fuzzer.multi_offRatio_deposit_neverDilutes(0, 0, 9e18, 5e8, 0); // zero slots → expected revert path
    fuzzer.multi_withdraw(0, 555);

    // lp vault (live position): deposit + withdraw.
    fuzzer.lp_deposit(6e18);
    fuzzer.lp_withdraw(4321);

    // fee vault: accrue fees first so solvency is exercised with a non-zero uncollected-fee component.
    fuzzer.fee_accrue_rewards(3e18, 2e18);
    fuzzer.fee_deposit(5e18);
    fuzzer.fee_withdraw(246);
  }

  /// @notice Prove the solvency bound is TIGHT (non-vacuous): after driving on-ratio deposits into the
  ///         multi vault, the sum of every holder's previewWithdraw must be within a few wei of total
  ///         balances. A loose/vacuous `<= totals` check would not constrain anything; this shows the sum
  ///         actually saturates totals (each floor loses < 1 wei, bounded by the holder count).
  function test_solvency_bound_is_tight_for_multi_vault() public {
    fuzzer.multi_deposit(0, 3e18);
    fuzzer.multi_deposit(1, 2e18);

    SharedVault v = fuzzer.multiVault();
    address[3] memory holders = [address(fuzzer), address(fuzzer.multiPlayers(0)), address(fuzzer.multiPlayers(1))];

    uint256[4] memory totals = v.getTotalBalances();
    uint256[4] memory owed;
    for (uint256 h; h < 3; h++) {
      uint256 bal = v.balanceOf(holders[h]);
      if (bal == 0) continue;
      uint256[4] memory pw = v.previewWithdraw(bal);
      for (uint256 i; i < 4; i++) {
        owed[i] += pw[i];
      }
    }

    // The harness holds INITIAL_SHARES + two players deposited, so there are 3 holders and 4 funded slots.
    assertEq(v.balanceOf(holders[0]) + v.balanceOf(holders[1]) + v.balanceOf(holders[2]), v.totalSupply(), "share conservation");
    for (uint256 i; i < 4; i++) {
      assertGt(totals[i], 0, "slot funded");
      assertLe(owed[i], totals[i], "solvency: holders cannot claim more than vault holds");
      // No LP positions in the multi vault, so previewWithdraw is exact: each holder's floor loses < 1 wei,
      // bounded by the 3 holders. Within 3 wei == the bound saturates totals (non-vacuous).
      assertGe(owed[i] + 3, totals[i], "solvency bound is tight (sum of previews ~= totals)");
    }
  }

  /// @notice HIGH-1: the three STANDALONE invariants (`assert_position_tracking_consistent`,
  ///         `assert_weth_mock_fully_backed`, `assert_all_backed_when_supply_exists`) are asserted by
  ///         NOTHING offline — the existing driver calls only handlers (which run share-conservation +
  ///         solvency internally), and the Echidna campaign can't compile here. Under a real Echidna run
  ///         these fire after every sequence; offline they fired never. Drive a mixed sequence to build
  ///         state across the position-bearing / weth / precision vaults, then assert all three directly.
  function test_standalone_invariants_hold_after_sequence() public {
    fuzzer.idle_deposit(0, 5e18, 5e18);
    fuzzer.multi_deposit(0, 2e18);
    fuzzer.lp_deposit(6e18);
    fuzzer.fee_accrue_rewards(3e18, 2e18);
    fuzzer.fee_deposit(5e18);
    fuzzer.precision_direct_deposit_floor(1); // mode 1 = exact deposit → precision vault gains supply

    fuzzer.assert_position_tracking_consistent(); // tracked arrays <= maxPositions, every entry pool-token
    fuzzer.assert_weth_mock_fully_backed(); // weth.balance == weth.totalSupply()
    fuzzer.assert_all_backed_when_supply_exists(); // positive backing for every vault with supply
  }

  /// @notice HIGH-2: `lp_drop_and_recover_position_keeps_vault_backed` is the only fuzz handler that
  ///         MUTATES the tracked-position array mid-run, and the existing driver never calls it. The LP
  ///         vault is seeded with positions at construction, so a drop→recover round-trip exercises NFT
  ///         custody transfer to/from the operator and re-asserts LP solvency / backing across a perturbed
  ///         positions array. Pair with the tracking-consistency invariant against the reshaped array.
  function test_lp_drop_recover_keeps_invariants() public {
    fuzzer.lp_deposit(6e18);
    fuzzer.lp_drop_and_recover_position_keeps_vault_backed(0);
    fuzzer.assert_position_tracking_consistent();
  }

  /// @notice MED-1: the precision vault had NO offline invariant coverage — the existing driver never
  ///         touches it, so `_assertPrecisionShareConservation` and the precision positive-backing check
  ///         never ran. Drive the below-floor revert branch, the exact-deposit branch, and the
  ///         below-floor withdraw-forwarding branch (which interleave a global setMinTokenPrecision flip
  ///         with deposits/withdraws — a sequence the unit tests don't reproduce), then assert conservation.
  function test_precision_vault_invariants_under_sequence() public {
    fuzzer.precision_direct_deposit_floor(0); // below-floor deposit must revert
    fuzzer.precision_direct_deposit_floor(1); // exact-floor deposit succeeds, harness gains precision shares
    fuzzer.precision_withdraw_forwards_below_floor(); // withdraw forwards a sub-floor remainder
    fuzzer.assert_precision_share_conservation();
  }

  /// @notice MED-2: the value-fairness handlers assert properties NOT implied by share-conservation /
  ///         solvency, and none are driven offline: donation-never-dilutes (supply untouched, donated slot
  ///         grows by exactly the donation, every holder's previewWithdraw only grows), deposit→withdraw
  ///         roundtrip-no-profit (rounding always favors the vault — incl. the mixed-decimals multi vault
  ///         where rounding-direction bugs surface), and remaining-holder value monotonicity under a
  ///         withdraw (LP + fee flavors; the fee flavor runs it under nonzero platform+owner fees).
  function test_value_fairness_invariants() public {
    // Seed holders so the donation/monotonicity handlers have shares to protect.
    fuzzer.idle_deposit(0, 5e18, 5e18);
    fuzzer.idle_deposit(1, 3e18, 3e18);
    fuzzer.lp_deposit(6e18);
    fuzzer.fee_accrue_rewards(3e18, 2e18);
    fuzzer.fee_deposit(5e18);

    fuzzer.idle_vault_token_donation_never_dilutes_holders(0, 1e18, false); // donate tokenA
    fuzzer.idle_vault_token_donation_never_dilutes_holders(1, 2e18, true); // donate tokenB

    fuzzer.idle_roundtrip_no_profit(2, 4e18, 4e18);
    fuzzer.multi_roundtrip_no_profit(1, 3e18);

    fuzzer.lp_withdraw_never_dilutes_remaining_holders(4321);
    fuzzer.fee_withdraw_never_dilutes_remaining_holders(246);
  }
}
