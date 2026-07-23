# RPC cache fixtures (hermetic fork gate)

These are Foundry's per-block RPC cache files (zstd-compressed), committed so the
fork/integration tests can run **offline** in CI with **zero live-node
dependency**. This is the "VCR cassette" pattern: real on-chain state is recorded
once and replayed deterministically.

## Why

The fork tests pin historical blocks (`vm.createFork(rpc, <block>)`). Public RPC
endpoints are flaky / rate-limited / archive-gated, which used to make CI fail for
pure infrastructure reasons. Replaying from these committed files removes the node
from the critical path entirely — see `plans/ci-fork-test-quarantine-design.md`.

## How CI uses them

The `fork-gate` job copies this tree into `~/.foundry/cache/rpc/` and runs the
fork tests with `--offline` + canonical URLs Foundry resolves without a probe
(`RPC_URL=https://mainnet.base.org`, `ECHIDNA_RPC_URL=https://mainnet.gateway.tenderly.co`).

```
test/fixtures/rpc-cache/<chain>/<block>   ->   ~/.foundry/cache/rpc/<chain>/<block>
```

## Contents

| Chain | Blocks | Used by |
|---|---|---|
| `base` | 27448360, 28445596, 34350500, 35350500, 36953600, 46190000 | all Base fork/integration tests |
| `mainnet` | 22365182 | echidna `ft.solo*` (Ethereum archive) |
| `mainnet` | 25596137 | `PrivateVaultBizFork` (pinned block where the real 7702 delegation is present) |
| `berachain` | 5249000 | `Integration.KodiakIsland` |

Total ≈ 770 KB.

`PrivateVaultBizFork` used to fork *latest* Ethereum (non-hermetic); it is now pinned
to `BIZ_FORK_BLOCK` (a block where `BIZ_7702_ACCOUNT` is delegated) and replayed from
the committed cache — so it runs **in the blocking gate** like everything else. To move
the pin, follow the note in `PrivateVaultBizFork.t.sol` and re-run the regen script.

## Regenerating

When the `fork-gate` job fails with "could not instantiate forked environment" or
a missing-cache error, a test started reading state not in these files. Refresh:

```sh
./scripts/regen-fork-cache.sh   # needs live RPCs in .env; then commit the diff
```

If you add a fork test on a **new block or chain**, add it to the arrays in
`scripts/regen-fork-cache.sh` and re-run.

## Version note

These files are a Foundry cache-format artifact. If CI's Foundry changes the
format, the job fails loudly (never silently wrong) — regenerate with a matching
Foundry version. CI installs `foundry-toolchain` (stable); regenerate locally with
the same major.
