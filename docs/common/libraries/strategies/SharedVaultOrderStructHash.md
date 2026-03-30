# Solidity API

## SharedVaultOrderStructHash

EIP-712 struct hash for SharedVault one-time user orders.
        Same shape as AgentAllowance but a distinct type hash, preventing cross-use.

### ORDER_TYPE_HASH

```solidity
bytes32 ORDER_TYPE_HASH
```

### SharedVaultOrder

```solidity
struct SharedVaultOrder {
  address vault;
  uint64 signatureTime;
  uint64 expirationTime;
}
```

### _hash

```solidity
function _hash(bytes encoded) internal pure returns (bytes32)
```

