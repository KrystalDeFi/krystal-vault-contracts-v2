# Echidna Fuzzer test

### Install

* Install echidna, slither

### To run

Private/public vault harnesses:

```sh
./run-echidna-test.sh VaultFuzzerSoloOwner
./run-echidna-test.sh VaultFuzzerWithSwap
./run-echidna-test.sh VaultFuzzerSoloPlayer
```

Shared-vault mock harness (`Fuzzer.sharedVault.sol`, config: `config.yaml`). Covers idle/multi-token/LP/WETH/precision vaults — the LP vault tracks TWO positions so deposits/withdraws iterate the positions array (including the swap-with-last removal reload) — a fee-bearing vault (10% platform + 5% vault-owner on collected LP rewards, including previewWithdraw-vs-withdraw parity), FOT / no-return tokens, gateway zaps, deposit→withdraw no-profit roundtrips, operator dropPosition/recoverPosition round-trips, and share-conservation / positive-backing invariants. Also fuzzed: share transfers between players (supply/backing conservation), the deposit-to-receiver overload, grantAdminRole/revokeAdminRole and transferOwnership round-trips (authorization flips both ways), operator sweeps (sweepTokens vault-token guard + junk sweep, sweepERC721 tracked-position guard, sweepERC1155 over-ask clamp, plain-ETH receive + sweepNativeToken), the account-overload withdraw with unwrap=true via allowance, local-vs-global pause isolation across vaults sharing one config manager, remaining-holder value monotonicity (`lp_withdraw_never_dilutes_remaining_holders` / `fee_withdraw_never_dilutes_remaining_holders`: one participant's withdraw must never decrease per-share per-token value for the holders who stay, cross-multiplied so floor rounding always favors the vault — the fee flavor runs it under nonzero platform+owner fees where the netted valuation must stay consistent with the realized collect), and position-tracking consistency (`assert_position_tracking_consistent`: the LP/fee vaults' tracked-position arrays never exceed `configManager.maxPositions()` and every tracked position references vault-configured tokens):

```sh
echidna test/echidna-fuzzer/Fuzzer.sharedVault.sol \
  --config test/echidna-fuzzer/config.yaml \
  --contract SharedVaultFuzzer
```

Shared-vault fork harness (`Fuzzer.sharedVaultFork.sol`, config: `config.sharedVaultFork.yaml`). Drives the real Base deployments: SharedV3Strategy proxy + Uniswap V3 NFPM, locally-compiled V4 / PancakeV4 / Aerodrome strategies against the real position managers — including mint AND partial-then-full owner exits (collectFees + exitProportional) for V4/Pancake. `ECHIDNA_RPC_URL` must point at Base; keep `--rpc-block` aligned with `BASE_FORK_BLOCK` in the harness:

```sh
echidna test/echidna-fuzzer/Fuzzer.sharedVaultFork.sol \
  --config test/echidna-fuzzer/config.sharedVaultFork.yaml \
  --contract SharedVaultForkFuzzer \
  --rpc-url "$ECHIDNA_RPC_URL" \
  --rpc-block 46190000
```

Both shared-vault configs pre-deploy and link the external libraries (`SharedVaultPreviewLib`, `SharedSwapDataSignature`, and on the fork config the V4/Pancake strategy + valuation libs); new handlers need no config changes unless they pull in a new linked library.
