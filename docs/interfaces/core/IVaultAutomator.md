# Solidity API

## IVaultAutomator

### InvalidOperator

```solidity
error InvalidOperator()
```

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
event CancelOrder(address user, bytes order, bytes signature)
```

### executeAllocate

```solidity
function executeAllocate(contract IVault vault, struct ICommon.Asset[] inputAssets, contract IStrategy strategy, bytes allocateCalldata, bytes abiEncodedUserOrder, bytes orderSignature) external
```

### executeSweepToken

```solidity
function executeSweepToken(contract IVault vault, address[] tokens) external
```

### executeSweepNFTToken

```solidity
function executeSweepNFTToken(contract IVault vault, address[] tokens, uint256[] tokenIds) external
```

### cancelOrder

```solidity
function cancelOrder(bytes abiEncodedUserOrder, bytes orderSignature) external
```

### isOrderCancelled

```solidity
function isOrderCancelled(bytes orderSignature) external view returns (bool)
```

### grantOperator

```solidity
function grantOperator(address operator) external
```

### revokeOperator

```solidity
function revokeOperator(address operator) external
```

