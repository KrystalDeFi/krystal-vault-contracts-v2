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
}
