# Solidity API

## MerklAutoClaimer

Contract that allows anyone to trigger Merkl reward claims through vault allocation

### OPERATOR_ROLE_HASH

```solidity
bytes32 OPERATOR_ROLE_HASH
```

### constructor

```solidity
constructor(address[] _allowedStrategies, address _owner) public
```

### claimRewards

```solidity
function claimRewards(contract IVault vault, address mekleStrategy, struct IMerklStrategy.ClaimAndSwapParams claimAndSwapParams) external
```

Claim Merkl rewards on behalf of a vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | The vault to claim rewards for |
| mekleStrategy | address |  |
| claimAndSwapParams | struct IMerklStrategy.ClaimAndSwapParams | Parameters for the Merkl reward claim |

### grantOperator

```solidity
function grantOperator(address operator) external
```

Grant operator role

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| operator | address | Operator address |

### revokeOperator

```solidity
function revokeOperator(address operator) external
```

Revoke operator role

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| operator | address | Operator address |

