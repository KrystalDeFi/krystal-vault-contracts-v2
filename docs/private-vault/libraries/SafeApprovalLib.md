# Solidity API

## SafeApprovalLib

Library for safe token approvals with reset functionality

_Provides utilities for safely approving tokens, including reset-and-approve pattern_

### ApproveFailed

```solidity
error ApproveFailed()
```

### safeApprove

```solidity
function safeApprove(contract IERC20 token, address spender, uint256 value) internal
```

Safe approve function that handles non-standard ERC20 tokens

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | contract IERC20 | The token to approve |
| spender | address | The spender address |
| value | uint256 | The amount to approve |

### safeResetAndApprove

```solidity
function safeResetAndApprove(contract IERC20 token, address spender, uint256 value) internal
```

Safe reset and approve function to handle tokens that require allowance to be 0 before setting new value

_First resets allowance to 0, then sets to desired value_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | contract IERC20 | The token to approve |
| spender | address | The spender address |
| value | uint256 | The amount to approve |

