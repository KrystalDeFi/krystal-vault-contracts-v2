# Solidity API

## SharedVaultAutomator

### OPERATOR_ROLE_HASH

```solidity
bytes32 OPERATOR_ROLE_HASH
```

### constructor

```solidity
constructor(address _owner, address[] _operators) public
```

### executeWithAgentAllowance

```solidity
function executeWithAgentAllowance(contract ISharedVault vault, struct ISharedVaultAutomator.Operation[] operations, bytes abiEncodedAgentAllowance, bytes signature) external
```

Execute operations against a vault using a long-lived AgentAllowance signature.

_**Security note**: the AgentAllowance struct commits only to (vault, signatureTime,
     expirationTime). It does NOT restrict which strategies, targets, or calldata the
     operator may use — any whitelisted operation on the vault is permitted until expiry.
     This is a broad delegation by design; vault owners should use short expiration
     windows and `cancelOrder` for early revocation. For one-time scoped operations,
     prefer `executeWithUserOrder`._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract ISharedVault | Vault to operate on |
| operations | struct ISharedVaultAutomator.Operation[] | Operations to execute |
| abiEncodedAgentAllowance | bytes | ABI-encoded AgentAllowance struct |
| signature | bytes | Vault owner's EIP-712 signature over the AgentAllowance |

### executeWithUserOrder

```solidity
function executeWithUserOrder(contract ISharedVault vault, struct ISharedVaultAutomator.Operation[] operations, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute operations against a vault using a user order signature.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract ISharedVault | Vault to operate on |
| operations | struct ISharedVaultAutomator.Operation[] | Operations to execute |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

### cancelOrder

```solidity
function cancelOrder(bytes32 hash, bytes signature) external
```

Cancel an order so it can never be replayed

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | EIP-712 digest that was signed |
| signature | bytes | The signature to cancel (must have been signed by msg.sender) |

### isOrderCancelled

```solidity
function isOrderCancelled(bytes signature) external view returns (bool)
```

Check whether an order signature has been cancelled

### grantOperator

```solidity
function grantOperator(address operator) external
```

Grant operator role to an address

### revokeOperator

```solidity
function revokeOperator(address operator) external
```

Revoke operator role from an address

### pause

```solidity
function pause() external
```

Pause the automator

### unpause

```solidity
function unpause() external
```

Unpause the automator

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view
```

Check if the caller has permission to withdraw

_Must be implemented by the child contract_

### receive

```solidity
receive() external payable
```

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

### _validateAgentAllowance

```solidity
function _validateAgentAllowance(bytes abiEncodedAgentAllowance, bytes signature, address vault) internal view
```

### _validateOrder

```solidity
function _validateOrder(bytes abiEncodedUserOrder, bytes orderSignature, address actor) internal view
```

_Validate the order_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |
| actor | address | Actor of the order |

### _executeOperations

```solidity
function _executeOperations(contract ISharedVault vault, struct ISharedVaultAutomator.Operation[] operations) internal
```

