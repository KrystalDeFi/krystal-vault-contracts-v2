# Solidity API

## SharedVault

### MAGIC_VALUE

```solidity
bytes4 MAGIC_VALUE
```

### SHARES_PRECISION

```solidity
uint256 SHARES_PRECISION
```

### configManager

```solidity
contract ISharedConfigManager configManager
```

### vaultOwner

```solidity
address vaultOwner
```

### vaultFactory

```solidity
address vaultFactory
```

### operator

```solidity
address operator
```

### tokenCount

```solidity
uint8 tokenCount
```

### tokens

```solidity
address[4] tokens
```

### isVaultToken

```solidity
mapping(address => bool) isVaultToken
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

### onlyOperator

```solidity
modifier onlyOperator()
```

### whenNotPaused

```solidity
modifier whenNotPaused()
```

### initialize

```solidity
function initialize(string _name, string _symbol, address[4] _tokens, uint256[4] initialAmounts, address _owner, address _configManager) public
```

Initializes the shared vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _name | string | Vault share token name |
| _symbol | string | Vault share token symbol |
| _tokens | address[4] | Up to 4 managed token addresses (address(0) = unused slot) |
| initialAmounts | uint256[4] | Initial deposit amounts (transferred by factory before this call) |
| _owner | address | Vault owner address |
| _configManager | address | Config manager address |

### deposit

```solidity
function deposit(uint256[4] amounts, uint256 minShares) external returns (uint256 shares)
```

Deposit tokens proportionally and receive shares

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amounts | uint256[4] | Amounts for each of the 4 token slots |
| minShares | uint256 | Minimum shares to receive |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares minted |

### withdraw

```solidity
function withdraw(uint256 shares, uint256[4] minAmounts) external returns (uint256[4] amounts)
```

Withdraw proportional idle tokens by burning shares

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares to burn |
| minAmounts | uint256[4] | Minimum amounts to receive per token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amounts | uint256[4] | Actual amounts returned |

### execute

```solidity
function execute(address strategy, bytes data) external payable
```

Execute LP operation via whitelisted strategy (delegatecall)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategy | address | Whitelisted strategy address |
| data | bytes | Encoded operation params |

### swap

```solidity
function swap(address swapTarget, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes swapData) external
```

Swap between vault tokens via whitelisted aggregator target

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| swapTarget | address | Whitelisted swap aggregator address |
| tokenIn | address | Input token (must be a vault token) |
| tokenOut | address | Output token (must be a vault token) |
| amountIn | uint256 | Amount of tokenIn to swap |
| minAmountOut | uint256 | Minimum amount of tokenOut to receive |
| swapData | bytes | Encoded swap call data for the aggregator |

### getTokens

```solidity
function getTokens() external view returns (address[4])
```

### getIdleBalances

```solidity
function getIdleBalances() external view returns (uint256[4])
```

### previewDeposit

```solidity
function previewDeposit(uint256[4] amounts) external view returns (uint256 shares)
```

### previewWithdraw

```solidity
function previewWithdraw(uint256 _shares) external view returns (uint256[4] amounts)
```

### sweepTokens

```solidity
function sweepTokens(address[] _tokens, uint256[] amounts, address to) external
```

Sweep non-vault ERC20 tokens (safeguard for stuck tokens)

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount, address to) external
```

Sweep native token

### sweepERC721

```solidity
function sweepERC721(address token, uint256 tokenId, address to) external
```

Sweep ERC721 token

### sweepERC1155

```solidity
function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external
```

Sweep ERC1155 token

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

### setOperator

```solidity
function setOperator(address _operator) external
```

### transferOwnership

```solidity
function transferOwnership(address newOwner) external
```

### isValidSignature

```solidity
function isValidSignature(bytes32 hash, bytes signature) public view returns (bytes4 magicValue)
```

_Should return whether the signature provided is valid for the provided data_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | Hash of the data to be signed |
| signature | bytes | Signature byte array associated with _data |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

### decimals

```solidity
function decimals() public pure returns (uint8)
```

_Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).

Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.

NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}._

### _getIdleBalances

```solidity
function _getIdleBalances() internal view returns (uint256[4] balances)
```

### receive

```solidity
receive() external payable
```

