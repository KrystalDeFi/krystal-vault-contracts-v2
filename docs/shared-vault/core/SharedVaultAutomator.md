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
function executeWithAgentAllowance(contract ISharedVault vault, struct ISharedVault.Action[] actions, bytes abiEncodedAgentAllowance, bytes signature) external
```

Execute actions against a vault using a long-lived AgentAllowance signature.

_**Security note**: the AgentAllowance struct commits only to (vault, signatureTime,
     expirationTime). It does NOT restrict which strategies, targets, or calldata the
     operator may use — any whitelisted operation on the vault is permitted until expiry.
     This is a broad delegation by design; vault owners should use short expiration
     windows and `cancelOrder` for early revocation. `executeWithUserOrder` is NOT a more
     restricted alternative (it is also reusable and does not bind the actions); this
     allowance is in fact the narrower primitive, as it commits to a specific vault and expiry._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract ISharedVault | Vault to operate on |
| actions | struct ISharedVault.Action[] | Same shape as `ISharedVault.execute` (`CallType.DELEGATECALL` for strategies, `CALL` for swaps) |
| abiEncodedAgentAllowance | bytes | ABI-encoded AgentAllowance struct |
| signature | bytes | Vault owner's EIP-712 signature over the AgentAllowance |

### executeWithUserOrder

```solidity
function executeWithUserOrder(contract ISharedVault vault, struct ISharedVault.Action[] actions, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute actions against a vault using a user order signature signed by the vault owner.

_**Security note**: like `executeWithAgentAllowance`, this is broad operator delegation — NOT a
     one-time or per-action authorization. The order signature is checked only for authenticity and
     not-cancelled state: it is NOT consumed (the same order may be re-executed until the owner
     calls `cancelOrder`), it does NOT bind the `actions` the operator submits, and the order struct
     carries no vault field (one signature is valid against every vault the same owner controls).
     The `OPERATOR_ROLE` holder is trusted to choose appropriate `actions`; the vault's own
     whitelist checks bound what those actions can do. Owners should sign sparingly and revoke via
     `cancelOrder`. For vault- and time-bounded delegation, prefer `executeWithAgentAllowance`._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract ISharedVault | Vault to operate on |
| actions | struct ISharedVault.Action[] | Same shape as `ISharedVault.execute` |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

### cancelOrder

```solidity
function cancelOrder(bytes32 hash, bytes signature) external
```

Cancel an order identified by its EIP-712 digest so it cannot be executed.

_Cancellation is keyed on the digest, not the raw signature bytes, so that
     EIP-1271 multisig wallets (which may produce different signature bytes for the
     same digest each time) cannot bypass cancellation with a fresh signature.
     Note: cancellation is only permanent if the owner does not re-sign a struct with
     identical field values (which would produce the same digest). AgentAllowance
     includes `signatureTime` and `expirationTime` as entropy; choosing new values
     yields a distinct hash that is not cancelled._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | EIP-712 digest that was signed |
| signature | bytes | The signature to cancel (must have been signed by msg.sender) |

### isOrderCancelled

```solidity
function isOrderCancelled(address actor, bytes32 hash) external view returns (bool)
```

Check whether `actor` has cancelled the order identified by its EIP-712 `hash`.

_Cancellation is scoped to the canceller (keyed on `(actor, hash)`), so this is per-actor:
     pass the order's signer (the vault owner) to learn whether a live order has been revoked.
     A different `actor` self-cancelling the same `hash` does not affect the owner's order._

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

