# Solidity API

## PrivateVault

### configManager

```solidity
contract IConfigManager configManager
```

### vaultOwner

```solidity
address vaultOwner
```

### vaultFactory

```solidity
address vaultFactory
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
function multicall(address[] targets, bytes[] data, enum IPrivateCommon.CallType[] callTypes) external payable
```

Batch multiple calls together (calls or delegatecalls)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| targets | address[] | Array of targets to call |
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

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

### receive

```solidity
receive() external payable
```

