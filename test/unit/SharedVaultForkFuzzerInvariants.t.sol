// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { SharedVaultForkFuzzer } from "../echidna-fuzzer/Fuzzer.sharedVaultFork.sol";

/// @title Deterministic driver for the FORK Echidna harness's security invariants
/// @notice The strongest security invariants in the suite — the V4 / PancakeV4 non-pool-token
///         anti-siphon rejections against the real, locally-compiled strategies — live in
///         `Fuzzer.sharedVaultFork.sol` (`SharedVaultForkFuzzer`). The existing forge driver
///         (`SharedVaultFuzzerInvariants.t.sol`) drives ONLY the mock harness, so offline / in CI the
///         fork invariants never execute, and the liveness flags `v4SecurityFiredAtLeastOnce` /
///         `pancakeV4SecurityFiredAtLeastOnce` are asserted by nothing — a campaign could skip the
///         security handlers silently. The full Echidna campaign can't run here (crytic-compile /
///         Foundry build-info mismatch), so this forge driver provides the offline, CI-runnable path:
///         it drives each property-style handler (which run their conservation / solvency / custody
///         asserts internally) and then asserts the standalone post-state views directly.
///
/// @dev    RUNTIME REQUIREMENT — this test forks Base at `BASE_FORK_BLOCK` (46,190,000), which is NEWER
///         than the integration cache (36.95M) and is therefore NOT in the local foundry cache. The
///         first run needs that block reachable via a live Base RPC (set `RPC_URL=https://mainnet.base.org`,
///         which warms the foundry cache); subsequent runs can use `--offline`. Under the command sandbox
///         (no mainnet.base.org access) this driver is COMPILE-ONLY; run it with
///         `dangerouslyDisableSandbox + FOUNDRY_OFFLINE=1` once the block is cached.
contract SharedVaultForkFuzzerInvariantsTest is Test {
  /// @dev Must match `SharedVaultForkFuzzer.BASE_FORK_BLOCK`.
  uint256 internal constant BASE_FORK_BLOCK = 46_190_000;

  SharedVaultForkFuzzer internal fuzzer;

  function setUp() public {
    // Pin the exact block the fork fuzzer's deployed-infrastructure constants were captured at, then
    // deploy the harness against that fork (its `constructor() payable` only deploys the swap-data signer;
    // all real-infrastructure wiring is lazy, triggered by the handlers below).
    vm.createSelectFork(vm.envString("RPC_URL"), BASE_FORK_BLOCK);
    fuzzer = new SharedVaultForkFuzzer();
  }

  /// @notice Drive the V4 + PancakeV4 anti-siphon handlers, then assert (a) the liveness flags prove the
  ///         security handlers actually ran (not silently skipped) and (b) the DAI bait is untouchable.
  /// @dev    The `assert_fork_*_dai_untouchable` views early-return until their `*HarnessReady` flag is
  ///         armed, so they MUST be called AFTER the driving handlers (which arm the harness on first call).
  function test_fork_v4_pancake_antiSiphon_invariants_hold() public {
    // Sweep a non-trivial gas-fee seed through each guard; any non-zero rate used to cause a siphon, so a
    // revert here (asserted inside the handler) proves the dangling non-pool input is rejected.
    fuzzer.fork_v4_swapAndMint_rejects_non_pool_input_token(uint64(1) << 60); // arms v4HarnessReady
    fuzzer.fork_pancake_v4_swapAndMint_rejects_non_pool_input_token(uint64(1) << 60); // arms pancakeV4HarnessReady

    // Liveness: fail loudly if a handler silently no-op'd instead of exercising the guard.
    assertTrue(fuzzer.v4SecurityFiredAtLeastOnce(), "V4 anti-siphon handler never executed");
    assertTrue(fuzzer.pancakeV4SecurityFiredAtLeastOnce(), "Pancake anti-siphon handler never executed");

    // Post-state anti-siphon assertions (no-op until armed, hence after the handlers above).
    fuzzer.assert_fork_v4_three_token_vault_dai_untouchable();
    fuzzer.assert_fork_pancake_v4_three_token_vault_dai_untouchable();
  }

  /// @notice Base round-trip + custody + share-conservation + aggregate-solvency invariants against the
  ///         real Base Uniswap V3 NFPM and the locally-compiled SharedVault implementation.
  /// @dev    Each handler runs its own conservation / backing asserts internally; the trailing
  ///         `assert_fork_*` views additionally pin the standalone post-state invariants that no handler
  ///         re-checks on its own — including the newly ported aggregate-solvency check.
  function test_fork_base_invariants_hold() public {
    fuzzer.fork_setup_real_position();
    fuzzer.fork_deposit(0, 1 ether);
    fuzzer.fork_deposit_withdraw_roundtrip_preserves_value(0, 2 ether);
    fuzzer.fork_external_donation_then_sweep_is_value_neutral(500 ether);

    fuzzer.assert_fork_share_conservation();
    fuzzer.assert_fork_uses_local_vault_implementation();
    fuzzer.assert_fork_position_owned_when_tracked();
    fuzzer.assert_fork_vault_backed();
    // Ported aggregate-solvency invariant: Σ holders previewWithdraw <= totals + (positionCount + 1) wei.
    fuzzer.assert_fork_solvency();
  }
}
