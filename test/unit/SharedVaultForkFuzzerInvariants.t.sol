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
/// @dev    Forks Base at `BASE_FORK_BLOCK` (46,190,000); CI serves the fork state from `test/fixtures/rpc-cache`.
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
    // The roundtrip's deposit was a basket the preview accepts, so it may not have been recorded as reverting.
    assertEq(fuzzer.livenessViolations(), 0, "a deposit the preview accepted reverted");
  }
}

/// @title Liveness invariants over the fork harness
/// @notice Same ghost-record pattern as the mock driver's SharedVaultLivenessInvariantsTest: with
///         `[invariant] fail_on_revert = false` a reverting handler call is dropped, so the harness's `fork_live_*`
///         handlers record a deposit the base vault's own views accept, or a withdrawal of 1 share up to a whole
///         balance, that reverted, and `invariant_fork_liveness` requires the record to stay empty. The base vault
///         holds a real Uniswap V3 WETH/USDC position on Base whose strategy runs the repo's SharedV3Strategy (the
///         harness points the deployed beacon at a local build). It forks Base at BASE_FORK_BLOCK, funds players by
///         writing balances, and targets only handlers that work on the vault's existing position (deposits,
///         withdrawals, dust donations, operator swaps, position top-ups).
contract SharedVaultForkLivenessInvariantsTest is Test {
  /// @dev Must match `SharedVaultForkFuzzer.BASE_FORK_BLOCK`.
  uint256 internal constant BASE_FORK_BLOCK = 46_190_000;

  SharedVaultForkFuzzer internal fuzzer;

  function setUp() public {
    vm.createSelectFork(vm.envString("RPC_URL"), BASE_FORK_BLOCK);
    fuzzer = new SharedVaultForkFuzzer();
    vm.deal(address(fuzzer), 10_000 ether); // native-ETH deposit legs
    fuzzer.fork_setup_real_position();
    // Both players start as depositors (a quarter of the supply each, one of them in native ETH), so withdrawals are
    // live from the first call.
    fuzzer.fork_live_deposit(0, 2, 1, 0, false);
    fuzzer.fork_live_deposit(1, 2, 1, 0, true);

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = SharedVaultForkFuzzer.fork_live_deposit.selector;
    selectors[1] = SharedVaultForkFuzzer.fork_live_withdraw.selector;
    selectors[2] = SharedVaultForkFuzzer.fork_live_donate.selector;
    selectors[3] = SharedVaultForkFuzzer.fork_deposit.selector;
    selectors[4] = SharedVaultForkFuzzer.fork_withdraw.selector;
    selectors[5] = SharedVaultForkFuzzer.fork_execute_call_swap.selector;
    selectors[6] = SharedVaultForkFuzzer.fork_increase_real_position.selector;
    targetContract(address(fuzzer));
    targetSelector(FuzzSelector({ addr: address(fuzzer), selectors: selectors }));

    // The handlers ignore msg.sender. One fixed sender keeps the campaign from loading a new fork account for every
    // random caller.
    address sender = makeAddr("forkLivenessSender");
    vm.deal(sender, 1 ether);
    targetSender(sender);
  }

  /// @notice No deposit the base vault's views accept and no withdrawal of 1 share up to a whole balance ever reverted.
  /// forge-config: default.invariant.runs = 16
  /// forge-config: default.invariant.depth = 12
  function invariant_fork_liveness() public view {
    _assertLive();
  }

  /// @notice Deposits into the vault holding the real V3 position (half the supply through the ERC-20 path at 0
  ///         slippage and with the WETH leg as msg.value at 0.5%; after dust donations, an operator swap and a
  ///         position top-up, a minimum-size native deposit at 1% and a quarter of the supply with excess USDC at 5%),
  ///         then withdrawals of 1 share, part of a balance and whole balances, with and without unwrapping.
  function test_fork_liveness_deposits_and_withdrawals_with_real_v3_position() public {
    // Counted from here, past the seed deposits in setUp.
    uint256 deposits = fuzzer.liveDeposits();
    uint256 nativeDeposits = fuzzer.liveNativeDeposits();
    uint256 slippageDeposits = fuzzer.liveSlippageDeposits();
    uint256 withdrawals = fuzzer.liveWithdrawals();

    fuzzer.fork_live_deposit(0, 1, 1, 0, false);
    fuzzer.fork_live_deposit(1, 1, 1, 49, true);
    fuzzer.fork_live_donate(false, 0); // 1 wei WETH
    fuzzer.fork_live_donate(true, 999); // 1_000 USDC units
    fuzzer.fork_execute_call_swap(0.05 ether);
    fuzzer.fork_increase_real_position(0.01 ether);
    fuzzer.fork_live_deposit(0, 63, 1, 99, true);
    fuzzer.fork_live_deposit(1, 2, 1284, 499, false); // 1284: +5% on the USDC slot
    // The property handlers' own deposits and partial withdrawal record a revert of a call that must go through too.
    fuzzer.fork_subsequent_deposit_proportional_invariant(0, 0.1 ether);
    fuzzer.fork_deposit_withdraw_roundtrip_preserves_value(1, 0.2 ether);
    fuzzer.fork_partial_withdraw_is_proportional(0, 2500);

    fuzzer.fork_live_withdraw(0, 1, false); // 1 share
    fuzzer.fork_live_withdraw(1, (uint256(1e18) << 8) | 5, true); // 1e18 + 1 shares, part of the balance
    fuzzer.fork_live_withdraw(0, 0, true); // whole balance
    fuzzer.fork_live_withdraw(1, 0, false); // whole balance

    _assertLive();
    assertEq(fuzzer.liveDeposits() - deposits, 4, "every deposit ran");
    assertEq(fuzzer.liveNativeDeposits() - nativeDeposits, 2, "two with msg.value");
    assertEq(fuzzer.liveSlippageDeposits() - slippageDeposits, 3, "three with slippage > 0");
    assertEq(fuzzer.liveWithdrawals() - withdrawals, 4, "every withdrawal ran");
    fuzzer.assert_fork_uses_local_v3_strategy();
    fuzzer.assert_fork_share_conservation();
    fuzzer.assert_fork_position_owned_when_tracked();
    fuzzer.assert_fork_solvency();
  }

  function _assertLive() internal view {
    assertEq(
      fuzzer.livenessViolations(),
      0,
      string.concat(
        "liveness: ", fuzzer.lastLivenessSite(), " reverted with ", vm.toString(fuzzer.lastLivenessRevert())
      )
    );
  }
}
