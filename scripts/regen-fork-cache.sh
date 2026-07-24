#!/usr/bin/env bash
#
# Regenerate the committed RPC cache fixtures used by the hermetic fork gate.
#
# WHEN TO RUN THIS:
#   The `fork-gate` CI job runs the fork tests with `--offline`, served entirely
#   from test/fixtures/rpc-cache/. If a change makes a fork test read on-chain
#   state (a block or storage slot) that isn't in the committed cache, the job
#   fails with "could not instantiate forked environment" or a missing-cache
#   error. That is the signal to run this script and commit the refreshed cache.
#
# WHAT IT DOES:
#   1. Runs the fork suite ONLINE (needs working RPCs, read from your .env) so
#      Foundry populates ~/.foundry/cache/rpc/ with every block+slot the tests
#      touch.
#   2. Copies the pinned block cache files into test/fixtures/rpc-cache/.
#
# REQUIREMENTS:
#   - .env with RPC_URL (Base), ECHIDNA_RPC_URL (Ethereum archive). See .env.example.
#   - The same Foundry major version as CI (cache format must match). Check with
#     `forge --version`; CI uses foundry-toolchain (stable).
#
# USAGE:  ./scripts/regen-fork-cache.sh
set -euo pipefail

cd "$(dirname "$0")/.."
FIXTURES="test/fixtures/rpc-cache"
CACHE="$HOME/.foundry/cache/rpc"

# Pinned blocks the hermetic fork gate needs, by chain. Keep in sync with the fork
# tests' block constants (base *_FORK_BLOCK, echidna BLOCK_NUMBER, BizFork BIZ_FORK_BLOCK).
# NOTE: BizFork's mainnet block (25596137) is REQUIRED below — it is pinned + hermetic,
# NOT "latest" — so it must stay in MAINNET_BLOCKS or the offline gate breaks.
BASE_BLOCKS=(27448360 28445596 34350500 35350500 36953600 46190000)
MAINNET_BLOCKS=(22365182 25596137)  # echidna ft.solo* (archive); BizFork (must match BIZ_FORK_BLOCK)
BERACHAIN_BLOCKS=(5249000)    # Integration.KodiakIsland

OSAKA='PrivateVaultAutomatorSmartWalletOwner|PrivateVaultAutomatorPasskeyOwner|PrivateVaultSmartWalletOwnerFork|PrivateVaultBizFork|PrivateVaultAutomator7702RawSig|PrivateVaultAutomator7702Integration'

# Non-hermetic tests are EXPLICITLY excluded from populate (they cannot be cached and
# would fail live): Katana (no Ronin archive) + HyperEVM (unreliable). Keep in sync with
# NON_HERMETIC_PATH in .github/workflows/pr-test.yaml. Everything else MUST pass online.
NON_HERMETIC='test/integration/Integration.{Katana,HyperEVM}*.t.sol'

echo ">> Populating ~/.foundry/cache/rpc via an ONLINE fork run (uses .env RPCs)..."
# Canonical Base + recognized Ethereum URLs so the same URLs resolve offline in CI.
# MAINNET_RPC_URL populates BizFork's pinned block (must serve state at BIZ_FORK_BLOCK —
# a recent block, so a full node suffices; for an old block use an archive endpoint).
: "${RPC_URL:=https://mainnet.base.org}"
: "${ECHIDNA_RPC_URL:=https://mainnet.gateway.tenderly.co}"
: "${MAINNET_RPC_URL:=https://mainnet.gateway.tenderly.co}"
export RPC_URL ECHIDNA_RPC_URL MAINNET_RPC_URL

# NO `|| true`: under `set -e` a failing populate aborts the script (non-zero) instead of
# silently copying stale/incomplete cache. A failure here means the fixtures would not be
# trustworthy — fix the suite / RPC access and re-run before committing.
forge test --via-ir --no-match-path "$NON_HERMETIC" --no-match-contract "$OSAKA"
forge test --via-ir --evm-version osaka --match-contract "$OSAKA"

echo ">> Copying pinned blocks into $FIXTURES ..."
missing=0
copy_chain() {
  local chain="$1"; shift
  mkdir -p "$FIXTURES/$chain"
  for b in "$@"; do
    if [[ -f "$CACHE/$chain/$b" ]]; then
      cp "$CACHE/$chain/$b" "$FIXTURES/$chain/$b"
      echo "   ✓ $chain/$b"
    else
      echo "   ✗ MISSING in cache: $chain/$b" >&2
      missing=1
    fi
  done
}
copy_chain base "${BASE_BLOCKS[@]}"
copy_chain mainnet "${MAINNET_BLOCKS[@]}"
copy_chain berachain "${BERACHAIN_BLOCKS[@]}"

# Authoritative trustworthiness gate: a required block absent means the populate run did
# not fetch it (RPC access / block too old). Fail non-zero so incomplete fixtures are
# never committed with a green exit.
if [[ "$missing" -ne 0 ]]; then
  echo ">> ERROR: required cache block(s) missing above — fixtures are INCOMPLETE. Do NOT commit." >&2
  echo ">>        Check RPC access and that pinned blocks are still served (BIZ_FORK_BLOCK is recent)." >&2
  exit 1
fi

echo ">> All required blocks present and copied — fixtures are complete and trustworthy."
echo ">> Review 'git status test/fixtures/rpc-cache' and commit the changes."
echo ">> Verify offline: RPC_URL=https://mainnet.base.org ECHIDNA_RPC_URL=https://mainnet.gateway.tenderly.co \\"
echo "     MAINNET_RPC_URL=https://mainnet.gateway.tenderly.co FOUNDRY_OFFLINE=true forge test --offline \\"
echo "     --via-ir --no-match-path '$NON_HERMETIC' --no-match-contract '$OSAKA'"
