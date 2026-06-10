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

Shared-vault mock harness (`Fuzzer.sharedVault.sol`, config: `config.yaml`). Covers idle/multi-token/LP/WETH/precision vaults, a fee-bearing vault (10% platform + 5% vault-owner on collected LP rewards, including previewWithdraw-vs-withdraw parity), FOT / no-return tokens, gateway zaps, deposit→withdraw no-profit roundtrips, and share-conservation / positive-backing invariants:

```sh
echidna test/echidna-fuzzer/Fuzzer.sharedVault.sol \
  --config test/echidna-fuzzer/config.yaml \
  --contract SharedVaultFuzzer
```

Shared-vault fork harness (`Fuzzer.sharedVaultFork.sol`, config: `config.sharedVaultFork.yaml`). Drives the real Base deployments: SharedV3Strategy proxy + Uniswap V3 NFPM, locally-compiled V4 / PancakeV4 / Aerodrome strategies against the real position managers. `ECHIDNA_RPC_URL` must point at Base; keep `--rpc-block` aligned with `BASE_FORK_BLOCK` in the harness:

```sh
echidna test/echidna-fuzzer/Fuzzer.sharedVaultFork.sol \
  --config test/echidna-fuzzer/config.sharedVaultFork.yaml \
  --contract SharedVaultForkFuzzer \
  --rpc-url "$ECHIDNA_RPC_URL" \
  --rpc-block 46190000
```

Both shared-vault configs pre-deploy and link the external libraries (`SharedVaultPreviewLib`, `SharedSwapDataSignature`, and on the fork config the V4/Pancake strategy + valuation libs); new handlers need no config changes unless they pull in a new linked library.
