# Solidity API

## IPrivateVaultAutomator

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

### executeMulticallWithAgentAllowance

```solidity
function executeMulticallWithAgentAllowance(contract IPrivateVault vault, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes, bytes abiEncodedAgentAllowance, bytes signature) external
```

### executeMulticallWithUserOrder

```solidity
function executeMulticallWithUserOrder(contract IPrivateVault vault, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes, bytes abiEncodedUserOrder, bytes orderSignature) external
```

### cancelOrder

```solidity
function cancelOrder(bytes32 hash, bytes signature) external
```

### isOrderCancelled

```solidity
function isOrderCancelled(bytes32 hash) external view returns (bool)
```

Check whether an order (identified by its EIP-712 digest) has been cancelled

### grantOperator

```solidity
function grantOperator(address operator) external
```

### revokeOperator

```solidity
function revokeOperator(address operator) external
```

