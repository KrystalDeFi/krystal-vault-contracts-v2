# Solidity API

## ISharedVaultAutomator

### InvalidSignature

```solidity
error InvalidSignature()
```

### OrderCancelled

```solidity
error OrderCancelled()
```

### CancelOrder

```solidity
event CancelOrder(address user, bytes32 hash, bytes signature)
```

### OpType

Operation type for the automator

```solidity
enum OpType {
  EXECUTE,
  SWAP
}
```

### Operation

A single operation to execute against a vault

```solidity
struct Operation {
  enum ISharedVaultAutomator.OpType opType;
  address target;
  bytes data;
  uint256 value;
}
```

### executeWithAgentAllowance

```solidity
function executeWithAgentAllowance(contract ISharedVault vault, struct ISharedVaultAutomator.Operation[] operations, bytes abiEncodedAgentAllowance, bytes signature) external payable
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
function executeWithUserOrder(contract ISharedVault vault, struct ISharedVaultAutomator.Operation[] operations, bytes abiEncodedUserOrder, bytes orderSignature) external payable
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

