# Solidity API

## VaultAutomator

### OPERATOR_ROLE_HASH

```solidity
bytes32 OPERATOR_ROLE_HASH
```

### constructor

```solidity
constructor(address _owner, address[] _operators) public
```

### executeAllocate

```solidity
function executeAllocate(contract IVault vault, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint64 gasFeeX64, bytes allocateData, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute an allocate on a Vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | Vault |
| inputAssets | struct AssetLib.Asset[] | Input assets |
| strategy | contract IStrategy | Strategy |
| gasFeeX64 | uint64 |  |
| allocateData | bytes | allocateData data to be passed to vault's allocate function |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

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

### executeSweepERC721

```solidity
function executeSweepERC721(contract IVault vault, address[] tokens, uint256[] tokenIds) external
```

Execute sweep NFT token ERC721

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | Vault address |
| tokens | address[] | Tokens to sweep |
| tokenIds | uint256[] | Token IDs to sweep |

### executeSweepERC1155

```solidity
function executeSweepERC1155(contract IVault vault, address[] tokens, uint256[] tokenIds, uint256[] amounts) external
```

Execute sweep NFT token ERC1155

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | Vault address |
| tokens | address[] | Tokens to sweep |
| tokenIds | uint256[] | Token IDs to sweep |
| amounts | uint256[] | Amounts to sweep |

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

### receive

```solidity
receive() external payable
```

