# CI Fork-Test Hermetic Gate — Design

**Date:** 2026-07-23
**Status:** Implemented
**Author:** brainstorming session (long.hoang@krystal.app)

> Evolution: started as "quarantine" (move forks off the blocking path) → upgraded
> to a **hermetic blocking gate** (fork state replayed from a committed cache) → then
> to **fail-loud** (no in-test skips: a test the gate selects must pass or fail
> loudly; tests that can't be hermetic are excluded *explicitly* in CI, not silenced).
> This doc describes the final (implemented) design.

## Problem

CI failed on nearly every PR with 37 "failing tests" that were **100%
infrastructure, 0% real** — each died in `setUp()` at `vm.createFork(...)`:

| Symptom | Endpoint | Cause |
|---|---|---|
| `-32601 Method not found` (35 Base forks) | `RPC_URL=https://base.merkle.io` | merkle.io lacks a method Foundry calls during fork instantiation |
| `403 Archive requires a token` (2 echidna) | `ECHIDNA_RPC_URL=https://ethereum-rpc.publicnode.com` | `ft.solo*` fork Ethereum **archive** state; publicnode gates it |

Every fork block is a *pinned constant*, so nothing needs a live chain tip. The git
log shows `chore: update CI RPC` **three times in five commits** — an RPC treadmill.

## Decision

- **Hermetic:** commit Foundry's per-block RPC cache as fixtures; CI restores them
  and runs the fork tests `--offline` with canonical URLs. No live node is contacted.
- **Fail-loud (no in-test skips):** the blocking gate selects only tests that *can*
  run hermetically. A missing/stale cache or misconfigured URL → `vm.createFork`
  **hard-fails (red)**, never a silent skip-to-green. Tests that physically cannot be
  hermetic are excluded **explicitly in the CI command** (a visible `--no-match`),
  not by an in-test `vm.skip`.
- **Minimal test-source change.** Fork `setUp`s stay pristine `vm.envString` (itself
  fail-loud: unset `RPC_URL` reverts clearly). The one exception: `BizFork` was pinned
  from *latest* to a fixed block (`BIZ_FORK_BLOCK = 25_596_137`) where the real 7702
  delegation is present — so it too becomes hermetic and joins the blocking gate. There
  is no non-blocking lane; every fork test gates.

## Validated assumptions (probed, forge 1.7.1)

1. Foundry resolves **canonical** URLs to a chain-id *without a live probe*, so
   `--offline` serves pinned blocks from the restored cache. Recognized offline:
   `https://mainnet.base.org` (Base), `https://mainnet.gateway.tenderly.co` /
   `https://eth.drpc.org` (Ethereum). NOT recognized (force a live probe):
   `base.merkle.io`, `base.llamarpc.com`, `eth.merkle.io`, forge-std's Alchemy default.
2. The RPC cache is one **zstd file per block** (`~/.foundry/cache/rpc/<chain>/<block>`),
   self-contained — committable and restorable by plain copy. Proven: with only the
   fixtures restored (real cache moved aside), representative forks on all 3 chains
   ran offline (82 passed, 0 failed).
3. `.env` is gitignored → absent in CI, so CI is naturally hermetic; a developer's
   `.env` still drives live forks locally.
4. `docs/` is wiped by `yarn docgen` (`rm -rf ./docs`) — hence this doc lives in `plans/`.

## Part 1 — Test source: near-unchanged (fail-loud by construction)

No guards, no skips added. Forking `setUp`s keep `vm.createFork(vm.envString("RPC_URL"), <block>)`.
The hermetic behaviour comes from CI supplying the canonical URL + restored cache; if
either is missing, the fork call fails loudly.

**One edit:** `BizFork` changed from `vm.createSelectFork(rpc)` (latest) to
`vm.createSelectFork(rpc, BIZ_FORK_BLOCK)` — a pinned block where `BIZ_7702_ACCOUNT` is
7702-delegated (`eth_getCode` == 23-byte `0xef0100…`). This makes it deterministic and
cacheable.

The only `vm.skip` in the codebase are **pre-existing** and out of scope: P256-precompile
availability (`PasskeyOwner`, `SmartWalletOwnerFork`) and BizFork delegation-liveness.
Under `--evm-version osaka` the P256 guards don't fire; at `BIZ_FORK_BLOCK` the delegation
is present so BizFork's liveness guard doesn't fire either → all run in the gate.

## Part 2 — Committed cache fixtures

`test/fixtures/rpc-cache/<chain>/<block>` (≈ 770 KB, 9 files), restored in CI into
`~/.foundry/cache/rpc/`. See that dir's `README.md` and `scripts/regen-fork-cache.sh`.

| Chain | Blocks | Used by |
|---|---|---|
| `base` | 27448360, 28445596, 34350500, 35350500, 36953600, 46190000 | all Base fork/integration |
| `mainnet` | 22365182 | echidna `ft.solo*` |
| `mainnet` | 25596137 | `PrivateVaultBizFork` (pinned; real 7702 delegation present) |
| `berachain` | 5249000 | `Integration.KodiakIsland` |

## Part 3 — CI: one blocking job in `pr-test.yaml`

Shared `env`: `OSAKA_CONTRACTS` (6 osaka-only contracts), `NON_HERMETIC_PATH`
(`Katana`/`HyperEVM` — excluded by path), `FORK_BASE_RPC=https://mainnet.base.org`,
`FORK_ETH_RPC=https://mainnet.gateway.tenderly.co`.

**Job `pr-test` (BLOCKING, hermetic, fail-loud):**
1. checkout / setup-node@18 / foundry-toolchain / `yarn install`
2. Restore fixtures: `cp -R test/fixtures/rpc-cache/{base,mainnet,berachain} ~/.foundry/cache/rpc/`
3. `forge test --offline --via-ir --no-match-path "$NON_HERMETIC_PATH" --no-match-contract "$OSAKA_CONTRACTS"`
   (cancun; canonical `RPC_URL`/`ECHIDNA_RPC_URL`; `FOUNDRY_OFFLINE=true`)
4. `forge test --offline --via-ir --evm-version osaka --match-contract "$OSAKA_CONTRACTS"`
   (osaka; canonical `RPC_URL` + `MAINNET_RPC_URL`; includes BizFork from cache)
5. `yarn docgen` + doc-commit.

No `vm.skip` fires in either step → every selected test passes or fails loud. There is
no non-blocking lane; all fork tests gate. Named `pr-test` to match the existing required
check — **no branch-protection change needed**.

### Why exclusion, not "let it fail (red)", for Katana + HyperEVM

Katana (no Ronin archive exists) and HyperEVM (mechanism unreliable, per team) *cannot*
run offline and are disabled. Running them in the gate would make it red on every PR —
the original problem. Excluding them **explicitly in the CI command** is the honest
middle: it's visible and greppable (not a silent in-test skip) and the reason is
documented in `env`. (BizFork *was* in this bucket until it was pinned to a cached block.)

## Trade-offs (accepted)

- **Cache maintenance is fail-loud:** if a change reads state not in the fixtures,
  the gate fails ("could not instantiate" / missing cache) — never silently green.
  Fix: `./scripts/regen-fork-cache.sh` + commit.
- **Binary blobs in git:** 770 KB of zstd cache. Small; git-lfs is overkill.
- **Foundry version coupling:** fixtures are a cache-format artifact; a format change
  fails the gate loudly → regenerate with the matching Foundry.
- **BizFork pin drift:** the pinned block freezes the real delegation as it was; if the
  test needs the *current* delegation, re-pin + regen. A recent block keeps it faithful.

## Out of scope

- Reducing fork usage in unit tests via mocking (the "too much fork" root).

## Verification (all offline)

| Check | Result |
|---|---|
| Fixtures-only clean-cache restore (3 chains) | 82 passed, 0 failed, 0 skipped |
| Gate — cancun step (fail-loud) | **1456 passed, 0 failed, 0 skipped** (77 suites) |
| Gate — osaka step (fail-loud, incl. BizFork) | **32 passed, 0 failed, 0 skipped** (6 suites) |
| BizFork offline at pinned block 25596137 | 6 passed, 0 failed, 0 skipped |

Note: `--no-match-path` is a **glob**, not a regex — an early regex attempt silently
matched nothing (letting HyperEVM run and fail with an empty RPC). Fail-loud caught it;
the working glob is `test/integration/Integration.{Katana,HyperEVM}*.t.sol`, verified to
exclude exactly those 4 files via `forge test --list`.

Repro (mimic CI):
```sh
cp -R test/fixtures/rpc-cache/{base,mainnet,berachain} ~/.foundry/cache/rpc/
RPC_URL=https://mainnet.base.org ECHIDNA_RPC_URL=https://mainnet.gateway.tenderly.co \
  FOUNDRY_OFFLINE=true forge test --offline --via-ir \
  --no-match-path '(Integration.Katana|Integration.HyperEVM)' --no-match-contract "$OSAKA_CONTRACTS"
```
