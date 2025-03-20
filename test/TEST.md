## TestSuites 

### Create A Vault
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
[] User can add liquidity from principal to a new LP position
[] User can add liquidity from principal to an existing LP position
[] User can remove liquidity from LP position to principal
    [] In all cases, total Vault value should remain the same (or changed insignificantly)
[] User can't add liquidity to a LP position which doesn't have principal in the pair
[] User can adjust 1 specific LP
    [] Rebalance
    [] Collect Fee


### Manage Public Vault (allowed deposit)
[] User can't add/rebalance LP which is smaller than the allowed range
    [] Case stable pairs, Case non-stable
[] User can't add to a LP which the pool is smaller the the allowed TVL, at the time of adding
[] User can't add to a LP which the pool is just created within the same block (to avoid flash-loan attack)
    [] Or if there is some way we could check the TVL in the previous block?
[] User can't add LP where the POOL_LIST is fixed and the pool is not in the POOL_LIST
