## TestSuites

### Shared Vault (contracts/shared-vault)

Coverage lives in three layers; the checklist below this section is the legacy private-vault plan.

* **Unit** (`test/unit/Shared*.t.sol`): core vault accounting (`SharedVault.t.sol`, incl. lifecycle-event
  emissions — SetVaultAdmin / VaultPausedUpdated / VaultOwnerChanged — owner/admin/operator privilege
  separation, and the fail-closed untrack guard when a still-owned position's valuation probe reverts),
  gateway zaps
  (`SharedVaultGateway.t.sol`), factory/automator/config-manager, strategy swap paths and signed-amount
  guards for the V3/Aerodrome twins (`SharedV3StrategySwapPath.t.sol` / `SharedAerodromeStrategySwapPath.t.sol`
  — keep these mirrored, the strategies are forks), valuation fee-accrual parity across V3/Aerodrome/V4/Pancake
  (`SharedStrategyFeeAccrual*.t.sol`, incl. the proportional-exit decrease→collect principal flow:
  params forwarded verbatim, principal never perf-fee'd, and the gas-only branch with its
  zero-principal / zero-recipient skip guards), hook gates, swap-data signature binding (incl. chain-id replay),
  the V4 swap pipeline and its Pancake normalization twin (`SharedV4SwapPipeline.t.sol` /
  `SharedPancakeV4SwapPipeline.t.sol` — keep these mirrored too),
  the V4/Pancake depositProportional slippage floor (`SharedV4DepositProportional.t.sol` /
  `SharedPancakeV4DepositProportional.t.sol` — mirrored twins),
  the V4/Pancake valuation libraries (`SharedV4ValuationLib.t.sol` / `SharedPancakeV4ValuationLib.t.sol`
  — mirrored twins: burned-token try/catch fallback, principal/fee split, F7 wrapped-fee-growth
  no-revert, the non-wrapping `hasCollectableFeesForFailedCollect` gate, and the out-of-range
  fee-growth-inside decomposition; the V4 file mocks the PoolManager at the storage-slot level so
  `StateLibrary`'s extsload slot math is exercised for real),
  and the preview-vs-applyFees wei-parity fuzz (`SharedVaultPreviewFeeParity.t.sol`, incl. the
  previewWithdraw owner-bps pre-clamp pin).
* **Integration** (`test/integration/Integration.SharedVault*.t.sol`): fork tests per protocol
  (V3/Sushi/Pancake V3, Aerodrome, Uniswap V4, Pancake V4), multi-protocol vaults, gateway, automator,
  and the vault `CALL` swap path.
* **Echidna** (`test/echidna-fuzzer/Fuzzer.sharedVault.sol` mock harness,
  `Fuzzer.sharedVaultFork.sol` Base-fork harness): see `test/echidna-fuzzer/readme.md`.

### Create A Vault (legacy private-vault checklist)
[x] User can create a Vault without any assets
[x] User can set a principal token from the whitelist, principal can't be changed

### Interact with a Vault
[x] User can deposit principal to mint shares
    [x] Deposit to a empty vault
    [x] Deposit to a vault with only principal
    [x] Deposit to a vault with both principal and LPs
    [x] Ratio between the assets remain unchanged

[x] User can burn shares to withdraw principals
    [x] Burn all shares
    [x] Burn partial shares
    [x] Burn 0 share
    [x] Ratio between the assets should remain unchanged
    [x] Received principal tokens should match the diff of the Vault Value

[x] User can't deposit non-principal token


### Allow Deposit
[x] User can turn ON allow_deposit for his private vault
[x] User can turn ON allow_deposit ONLY ONCE
    [x] Call the the 2nd time with different config returns error

[x] User cannot Turn off allow_deposit once it's on

[x] User can Allow Deposit with proper Vault Config
    [x] RANGE_Config, TVL_Config can't be UNSET
    [x] LIST_POOL can be UNSET or A Fixed List
    [x] Existing assets should follow the vault config
    

### Manage Private Vault (ALLOW_DEPOSIT = false, UNSET RANGE, TVL, LIST_POOL)
[x] User can add liquidity from principal to a new LP position
[x] User can add liquidity from principal to an existing LP position
[x] User can remove liquidity from LP position to principal
    [x] In all cases, total Vault value should remain the same (or changed insignificantly)
[x] User can't add liquidity to a LP position which doesn't have principal in the pair
[x] User can adjust 1 specific LP
    [x] Rebalance
    [x] Collect Fee


### Manage Public Vault (allowed deposit)
[x] User can't add/rebalance LP which is smaller than the allowed range
    [x] Case stable pairs
    [] Case non-stable
[x] User can't add to a LP which the pool is smaller the the allowed TVL, at the time of adding
[] User can't add to a LP which the pool is just created within the same block (to avoid flash-loan attack)
    [] Or if there is some way we could check the TVL in the previous block?
[x] User can't add LP where the POOL_LIST is fixed and the pool is not in the POOL_LIST
