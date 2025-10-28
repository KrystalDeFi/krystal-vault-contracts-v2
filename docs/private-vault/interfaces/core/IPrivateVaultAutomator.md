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

### executeMulticall

```solidity
function executeMulticall(contract IPrivateVault vault, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes, bytes32 hash, bytes signature) external
```

### executeMulticall

```solidity
function executeMulticall(contract IPrivateVault vault, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes, bytes abiEncodedUserOrder, bytes orderSignature) external
```

### cancelOrder

```solidity
function cancelOrder(bytes32 hash, bytes signature) external
```

### isOrderCancelled

```solidity
function isOrderCancelled(bytes signature) external view returns (bool)
```

### grantOperator

```solidity
function grantOperator(address operator) external
```

### revokeOperator

```solidity
function revokeOperator(address operator) external
```

