## TestSuites 

### Create A Vault
- User can create a Vault without any assets
- User can set a principal token from the whitelist, principal can't be changed

### Interact with a Vault
- User can deposit principal to mint shares
    - Deposit to a empty vault
    - Deposit to a vault with only principal
    - Deposit to a vault with both principal and LPs
    - Ratio between the assets remain unchanged

- User can burn shares to withdraw principals
    - Burn all shares
    - Burn partial shares
    - Burn 0 share
    - Ratio between the assets should remain unchanged
    - Received principal tokens should match the diff of the Vault Value


- User can't deposit non-principal token


### Allow Deposit
- User can turn ON allow_deposit only once
    - Call the the 2nd time with different config returns error

- User cannot Turn off allow_deposit once it's on

- User can Allow Deposit with proper Vault Config
    - RANGE_Config, TVL_Config can't be UNSET
    - LIST_POOL can be UNSET or A Fixed List
    - Existing assets should follow the vault config
    

### Manage Private Vault (ALLOW_DEPOSIT = false, UNSET RANGE, TVL, LIST_POOL)
- User can add liquidity from principal to a new LP position
- User can add liquidity from principal to an existing LP position
- User can remove liquidity from LP position to principal
    - In all cases, total Vault value should remain the same (or changed insignificantly)
- User can't add liquidity to a LP position which doesn't have principal in the pair
- User can adjust 1 specific LP
    - Rebalance
    - Collect Fee


### Manage Public Vault (allowed deposit)
- User can't 
