# Solidity API

## Withdrawable

Abstract contract providing sweep functions for native tokens, ERC20, ERC721, and ERC1155 tokens

_Child contracts must implement the `_checkWithdrawPermission` modifier to enforce access control_

### onlyWithdrawer

```solidity
modifier onlyWithdrawer()
```

_Modifier to check if the caller has permission to withdraw
Must be implemented by the child contract_

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view virtual
```

Check if the caller has permission to withdraw

_Must be implemented by the child contract_

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount) external
```

Sweep native token to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount of native token to sweep |

### sweepERC20

```solidity
function sweepERC20(address[] tokens, uint256[] amounts) external
```

Sweeps ERC20 tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |
| amounts | uint256[] | Amounts of tokens to sweep |

### sweepERC721

```solidity
function sweepERC721(address[] tokens, uint256[] tokenIds) external
```

Sweeps ERC721 tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |
| tokenIds | uint256[] | Token IDs to sweep |

### sweepERC1155

```solidity
function sweepERC1155(address[] tokens, uint256[] tokenIds, uint256[] amounts) external
```

Sweeps ERC1155 tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |
| tokenIds | uint256[] | Token IDs to sweep |
| amounts | uint256[] | Amounts of tokens to sweep |

