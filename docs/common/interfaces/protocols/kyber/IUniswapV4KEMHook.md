# Solidity API

## IUniswapV4KEMHook

### claimEgTokens

```solidity
function claimEgTokens(address[] tokens, uint256[] amounts) external
```

Claim some of equilibrium-gain tokens accrued by the hook
Can only be called by the claimable accounts

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | the addresses of the tokens to claim |
| amounts | uint256[] | the amounts of the tokens to claim, set to 0 to claim all |

