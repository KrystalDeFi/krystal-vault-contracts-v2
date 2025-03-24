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
function executeAllocate(contract IVault vault, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint16 gasFeeBasisPoint, bytes allocateCalldata, bytes abiEncodedUserOrder, bytes orderSignature) external
```

### executeSweepToken

```solidity
function executeSweepToken(contract IVault vault, address[] tokens) external
```

### executeSweepERC721

```solidity
function executeSweepERC721(contract IVault vault, address[] tokens, uint256[] tokenIds) external
```

### executeSweepERC1155

```solidity
function executeSweepERC1155(contract IVault vault, address[] tokens, uint256[] tokenIds, uint256[] amounts) external
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

