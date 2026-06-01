# Echidna Fuzzer Tests

## Install

Echidna is managed via devbox. Run once to install:

```sh
devbox install
```

Then enter the devbox shell before running any fuzzer:

```sh
devbox shell
```

## Public Vault fuzzers (Ethereum mainnet fork)

These test the original `Vault` contract.

```sh
./run-echidna-test.sh VaultFuzzerSoloOwner
./run-echidna-test.sh VaultFuzzerWithSwap
./run-echidna-test.sh VaultFuzzerSoloPlayer
```

## SharedVault fuzzers (Base mainnet fork)

These test the `SharedVault` contract family. Each targets a different scenario:

| Contract | Scenario | Properties checked |
|---|---|---|
| `SharedVaultFuzzerSoloOwner` | Owner + 2 players deposit; owner tries to drain | Owner can't profit at players' expense; share supply consistency |
| `SharedVaultFuzzerMultiPlayer` | 3 equal players deposit/withdraw in random order | Share supply consistency; no player withdraws more than deposited |
| `SharedVaultFuzzerWithStrategy` | Owner opens LP positions; players deposit/withdraw | Fee basis point immutability; share supply consistency; no player profits |

```sh
./run-echidna-test.sh SharedVaultFuzzerSoloOwner
./run-echidna-test.sh SharedVaultFuzzerMultiPlayer
./run-echidna-test.sh SharedVaultFuzzerWithStrategy
```

The script auto-selects the Base RPC for `SharedVaultFuzzer*` contracts. Override with:

```sh
BASE_RPC_URL=https://your-base-rpc ./run-echidna-test.sh SharedVaultFuzzerSoloOwner
```

## Foundry companions (for debugging failing sequences)

Each echidna fuzzer has a matching `ft.*` Foundry test for reproducing failures locally:

```sh
RPC_URL=<base-rpc-url> forge test --match-contract FtSharedVaultSoloOwner -vvv
RPC_URL=<base-rpc-url> forge test --match-contract FtSharedVaultMultiPlayer -vvv
RPC_URL=<base-rpc-url> forge test --match-contract FtSharedVaultWithStrategy -vvv
```

## Notes

- ERC20 balance funding uses `hevm.store` to write directly to storage slots. If a fuzzer constructor reverts with token transfer errors, the storage slot constants in `test/echidna-fuzzer/SharedVaultConfig.sol` may be wrong for the current Base fork. Run the slot-check script in `docs/superpowers/plans/2026-05-11-sharedvault-echidna-fuzzer.md` (Task 8.1) to find the correct values.
- `testMode: assertion` — echidna checks `echidna_*` boolean properties after every call sequence.
- `allContracts: true` — echidna probes helper contracts too; this is harmless as none define `echidna_*` properties.
