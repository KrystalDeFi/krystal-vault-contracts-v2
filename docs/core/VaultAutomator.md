# Solidity API

## VaultAutomator

### OPERATOR_ROLE_HASH

```solidity
bytes32 OPERATOR_ROLE_HASH
```

### constructor

```solidity
constructor() public
```

### executeRebalance

```solidity
function executeRebalance(struct IVaultAutomator.ExecuteRebalanceParams params) external
```

Execute a rebalance on a KrystalVault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct IVaultAutomator.ExecuteRebalanceParams | ExecuteRebalanceParams |

### executeExit

```solidity
function executeExit(contract IVault vault, uint256 amount0Min, uint256 amount1Min, uint16 automatorFee, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute exit on a KrystalVault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | KrystalVault to exit from |
| amount0Min | uint256 | Minimum amount of token0 to receive |
| amount1Min | uint256 | Minimum amount of token1 to receive |
| automatorFee | uint16 |  |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

### executeCompound

```solidity
function executeCompound(contract IVault vault, uint256 amount0Min, uint256 amount1Min, uint16 automatorFee, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute compound on a KrystalVault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | KrystalVault to compound |
| amount0Min | uint256 | Minimum amount of token0 to receive |
| amount1Min | uint256 | Minimum amount of token1 to receive |
| automatorFee | uint16 |  |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

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

### cancelOrder

```solidity
function cancelOrder(bytes abiEncodedUserOrder, bytes orderSignature) external
```

Cancel an order

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

### isOrderCancelled

```solidity
function isOrderCancelled(bytes orderSignature) external view returns (bool)
```

Check if an order is cancelled

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| orderSignature | bytes | Signature of the order |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | true if the order is cancelled |

### grantOperator

```solidity
function grantOperator(address operator) external
```

Grant operator role

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| operator | address | Operator address |

### revokeOperator

```solidity
function revokeOperator(address operator) external
```

Revoke operator role

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| operator | address | Operator address |

### executeSweepToken

```solidity
function executeSweepToken(contract IVault vault, address[] tokens) external
```

Execute sweep token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | Vault address |
| tokens | address[] | Tokens to sweep |

### executeSweepNFTToken

```solidity
function executeSweepNFTToken(contract IVault vault, address[] tokens, uint256[] tokenIds) external
```

Execute sweep NFT token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | Vault address |
| tokens | address[] | Tokens to sweep |
| tokenIds | uint256[] | Token IDs to sweep |

### receive

```solidity
receive() external payable
```

