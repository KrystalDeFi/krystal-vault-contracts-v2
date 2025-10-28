# Solidity API

## PrivateVaultAutomator

### OPERATOR_ROLE_HASH

```solidity
bytes32 OPERATOR_ROLE_HASH
```

### constructor

```solidity
constructor(address _owner, address[] _operators) public
```

### executeMulticall

```solidity
function executeMulticall(contract IPrivateVault vault, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes, bytes32 hash, bytes signature) external
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IPrivateVault | Vault |
| targets | address[] | Targets to call |
| callValues | uint256[] | Call values |
| data | bytes[] | Data to pass to the calls |
| callTypes | enum IPrivateCommon.CallType[] | Call types |
| hash | bytes32 | Hash of the data to be signed |
| signature | bytes | Signature of the order |

### executeMulticall

```solidity
function executeMulticall(contract IPrivateVault vault, address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute a multicall with EIP-712 signature verification

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IPrivateVault | Vault |
| targets | address[] | Targets to call |
| callValues | uint256[] | Call values |
| data | bytes[] | Data to pass to the calls |
| callTypes | enum IPrivateCommon.CallType[] | Call types |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

### _validateOrder

```solidity
function _validateOrder(bytes32 hash, bytes signature, address actor) internal view
```

_Validate the order_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | Hash of the data to be signed |
| signature | bytes | Signature of the order |
| actor | address | Actor of the order |

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
function cancelOrder(bytes32 hash, bytes signature) external
```

Cancel an order

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | Hash of the data to be signed |
| signature | bytes | Signature of the order |

### isOrderCancelled

```solidity
function isOrderCancelled(bytes signature) external view returns (bool)
```

Check if an order is cancelled

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| signature | bytes | Signature of the order |

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

### pause

```solidity
function pause() external
```

Pause the contract

### unpause

```solidity
function unpause() external
```

Unpause the contract

### receive

```solidity
receive() external payable
```

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

