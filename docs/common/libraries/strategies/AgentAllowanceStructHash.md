# Solidity API

## AgentAllowanceStructHash

### _hash

```solidity
function _hash(bytes abiEncodedAgentAllowance) internal pure returns (bytes32)
```

### AGENT_ALLOWANCE_TYPE_HASH

```solidity
bytes32 AGENT_ALLOWANCE_TYPE_HASH
```

### AgentAllowance

Broad-scope delegation: the signed allowance does NOT commit to specific
        strategies, targets, or operation data. Signing grants any automator operator
        permission to execute arbitrary whitelisted operations on the vault until
        `expirationTime`. Vault owners should set short expiration windows and may
        revoke early via `cancelOrder`. For one-time scoped operations, prefer
        `executeWithUserOrder` which consumes the signature after a single use.

```solidity
struct AgentAllowance {
  address vault;
  uint64 signatureTime;
  uint64 expirationTime;
}
```

