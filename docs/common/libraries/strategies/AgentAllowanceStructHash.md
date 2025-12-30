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

```solidity
struct AgentAllowance {
  address vault;
  uint64 signatureTime;
  uint64 expirationTime;
}
```

