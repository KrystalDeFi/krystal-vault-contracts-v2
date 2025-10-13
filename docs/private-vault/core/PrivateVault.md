# Solidity API

## PrivateVault

### MAGIC_VALUE

```solidity
bytes4 MAGIC_VALUE
```

### vaultOwner

```solidity
address vaultOwner
```

### vaultFactory

```solidity
address vaultFactory
```

### configManager

```solidity
contract IPrivateConfigManager configManager
```

### admins

```solidity
mapping(address => bool) admins
```

### onlyOwner

```solidity
modifier onlyOwner()
```

### onlyAuthorized

```solidity
modifier onlyAuthorized()
```

### whenNotPaused

```solidity
modifier whenNotPaused()
```

### initialize

```solidity
function initialize(address _owner, address _configManager) public
```

Initializes the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _owner | address | Owner of the vault |
| _configManager | address | Address of the whitelist manager |

### multicall

```solidity
function multicall(address[] targets, uint256[] callValues, bytes[] data, enum IPrivateCommon.CallType[] callTypes) external payable
```

Batch multiple calls together (calls or delegatecalls)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| targets | address[] | Array of targets to call |
| callValues | uint256[] |  |
| data | bytes[] | Array of data to pass with the calls |
| callTypes | enum IPrivateCommon.CallType[] | Array of call types (CALL or DELEGATECALL) |

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount) external
```

Sweep native token to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount of native token to sweep |

### sweepToken

```solidity
function sweepToken(address[] tokens, uint256[] amounts) external
```

Sweeps the tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |
| amounts | uint256[] | Amounts of tokens to sweep |

### sweepERC721

```solidity
function sweepERC721(address[] _tokens, uint256[] _tokenIds) external
```

Sweeps the non-fungible tokens ERC721 to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _tokens | address[] | Tokens to sweep |
| _tokenIds | uint256[] | Token IDs to sweep |

### sweepERC1155

```solidity
function sweepERC1155(address[] _tokens, uint256[] _tokenIds, uint256[] _amounts) external
```

Sweep ERC1155 tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _tokens | address[] | Tokens to sweep |
| _tokenIds | uint256[] | Token IDs to sweep |
| _amounts | uint256[] | Amounts of tokens to sweep |

### depositErc20Tokens

```solidity
function depositErc20Tokens(address[] tokens, uint256[] amounts) external
```

Deposits ERC20 tokens to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Array of ERC20 token addresses |
| amounts | uint256[] | Array of amounts to deposit |

### depositErc721Tokens

```solidity
function depositErc721Tokens(address[] tokens, uint256[] tokenIds) external
```

Deposits ERC721 tokens to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Array of ERC721 token addresses |
| tokenIds | uint256[] | Array of token IDs to deposit |

### depositErc1155Tokens

```solidity
function depositErc1155Tokens(address[] tokens, uint256[] tokenIds, uint256[] amounts) external
```

Deposits ERC1155 tokens to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Array of ERC1155 token addresses |
| tokenIds | uint256[] | Array of token IDs to deposit |
| amounts | uint256[] | Array of amounts to deposit |

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

grant admin role to the address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _address | address | The address to which the admin role is granted |

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

revoke admin role from the address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _address | address | The address from which the admin role is revoked |

### isValidSignature

```solidity
function isValidSignature(bytes32 hash, bytes signature) public view returns (bytes4 magicValue)
```

EIP-1271 signature validation

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | The hash of the data to be signed |
| signature | bytes | The signature to be validated |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| magicValue | bytes4 | The magic value if the signature is valid, otherwise 0xffffffff |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

### receive

```solidity
receive() external payable
```

