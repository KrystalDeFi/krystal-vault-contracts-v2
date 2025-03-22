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
