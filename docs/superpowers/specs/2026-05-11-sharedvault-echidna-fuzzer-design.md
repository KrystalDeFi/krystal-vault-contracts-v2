# SharedVault Echidna Fuzzer Design

## Overview

Add Echidna fuzz tests for the `SharedVault` contract family, following the same structure as the existing public-vault echidna fuzzers (`test/echidna-fuzzer/`). Uses a forked Ethereum/Base mainnet via `hevm.roll` + `BANK_ADDRESS` funding, run via an extended `run-echidna-test.sh`.

## Scenarios

Three fuzzer contracts, one file each, placed in `test/echidna-fuzzer/`:

| File | Scenario | Key Actors |
|---|---|---|
| `Fuzzer.SharedVault.soloOwner.sol` | Owner creates vault, deposits, 2 players deposit, owner tries to withdraw all | owner, player1, player2 |
| `Fuzzer.SharedVault.multiPlayer.sol` | 3 equal players deposit, random withdrawals, random ordering | player1, player2, player3 |
| `Fuzzer.SharedVault.withStrategy.sol` | Like multiPlayer but owner also calls `execute()` to open/close LP via SharedV3Strategy | owner, player1, player2 |

Matching foundry test variants (`ft.SharedVault.*.sol`) are added alongside each fuzzer for local development/debugging, same as `ft.soloOwner.sol` mirrors `fuzzer.soloOwner.sol`.

## Setup Pattern

Each fuzzer constructor:
1. `hevm.roll(BLOCK_NUMBER)` + `hevm.warp(BLOCK_TIMESTAMP)` — pin fork state
2. Fund actors from `BANK_ADDRESS` (whale on forked chain)
3. Deploy `SharedConfigManager`, `SharedVaultFactory`, `SharedVault` implementation
4. Whitelist `SharedV3Strategy` in config manager
5. Owner creates vault via factory with initial token amounts (WETH + USDC on Base fork)
6. Players deposit initial amounts

Chain: Base mainnet (block ~36_953_600), tokens: WETH + USDC (matching integration tests).

## Properties

### Simple (Fuzzers 1 & 2 — no LP)

1. `ownerTokenBalance <= INITIAL_TOKEN_BALANCE` — owner cannot extract more than deposited
2. `vault.totalSupply() == sum(balanceOf(allActors))` — share accounting consistency
3. After all actors withdraw fully, `vault.totalSupply() == 0`
4. No player's withdrawal value exceeds their proportional share (within `vaultOwnerFeeBasisPoint` tolerance)

### Complex (Fuzzer 3 — with LP strategy)

5. `getTotalBalances()[i] >= 0` for all token slots — no balance underflow
6. `vaultOwnerFeeBasisPoint` equals the value set at init (immutable check)
7. `getPositionCount()` stays consistent with `execute()` calls — no phantom positions
8. `previewWithdraw(shares)` approximates actual withdraw output (within configured slippage)

## Files to Create

```
test/echidna-fuzzer/
  SharedVaultConfig.sol              # constants: tokens, block, bank address (Base fork)
  SharedVaultPlayer.sol              # Player helper for SharedVault calls
  Fuzzer.SharedVault.soloOwner.sol
  Fuzzer.SharedVault.multiPlayer.sol
  Fuzzer.SharedVault.withStrategy.sol
  ft.SharedVault.soloOwner.sol       # foundry dev/debug companion
  ft.SharedVault.multiPlayer.sol
  ft.SharedVault.withStrategy.sol
```

## Tooling

Echidna is managed via **devbox** (`devbox.json`). The `echidna` package must be added to devbox before running tests. Run all echidna commands inside `devbox shell`.

## Run Script

Extend `run-echidna-test.sh` to accept the new contract names:
```sh
./run-echidna-test.sh SharedVaultFuzzerSoloOwner
./run-echidna-test.sh SharedVaultFuzzerMultiPlayer
./run-echidna-test.sh SharedVaultFuzzerWithStrategy
```

## Out of Scope

- Gateway (`SharedVaultGateway`) fuzzing — deferred, more complex swap setup
- V4/Aerodrome strategy fuzzing — deferred
- Invariant mode (Foundry) — separate effort
