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

### weth

```solidity
address weth
```

### tokenCount

```solidity
uint16 tokenCount
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

### paused

```solidity
bool paused
```

### positions

```solidity
struct ISharedVault.Position[] positions
```

_Array of tracked LP positions_

### positionIndex

```solidity
mapping(bytes32 => uint256) positionIndex
```

_Quick lookup: keccak256(nfpm, tokenId) => index+1 (0 = not tracked)_

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
function initialize(string _name, address[4] _tokens, uint256[4] initialAmounts, address _owner, address _configManager, address _weth) public
```

Initializes the shared vault

### deposit

```solidity
function deposit(uint256[4] amounts, uint256 minShares) external payable returns (uint256 shares)
```

Deposit tokens proportionally and receive shares

_Share ratio is based on TOTAL balances (idle + LP positions valued by strategies).
     Send ETH via msg.value to auto-wrap to WETH; amounts[wethIndex] must equal msg.value._

### withdraw

```solidity
function withdraw(uint256 shares, uint256[4] minAmounts, bool unwrap) external returns (uint256[4] amounts)
```

Withdraw proportional IDLE tokens by burning shares

_Uses total balances for share ratio but only withdraws idle tokens.
     If tokens are deployed to LP, withdrawer gets proportional idle only._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 |  |
| minAmounts | uint256[4] |  |
| unwrap | bool | If true, any WETH output is unwrapped to native ETH before sending. |

### execute

```solidity
function execute(address strategy, bytes data) external payable
```

Execute LP operation via whitelisted strategy (delegatecall)

_Strategy returns position changes which the vault tracks with the strategy address_

### swap

```solidity
function swap(address swapTarget, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes swapData) external
```

Swap between vault tokens via whitelisted aggregator target

### getTokens

```solidity
function getTokens() external view returns (address[4])
```

### getIdleBalances

```solidity
function getIdleBalances() external view returns (uint256[4])
```

### getTotalBalances

```solidity
function getTotalBalances() external view returns (uint256[4])
```

### getPositionCount

```solidity
function getPositionCount() external view returns (uint256)
```

### getPosition

```solidity
function getPosition(uint256 index) external view returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1)
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

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount, address to) external
```

### sweepERC721

```solidity
function sweepERC721(address token, uint256 tokenId, address to) external
```

### sweepERC1155

```solidity
function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external
```

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

### setPaused

```solidity
function setPaused(bool _paused) external
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

### _addPosition

```solidity
function _addPosition(address strategy, address nfpm, uint256 tokenId, address token0, address token1) internal
```

### _removePosition

```solidity
function _removePosition(address nfpm, uint256 tokenId) internal
```

### _wethIndex

```solidity
function _wethIndex() internal view returns (uint256)
```

_Returns the index of the WETH token in the tokens array, or type(uint256).max if not found._

### _getIdleBalances

```solidity
function _getIdleBalances() internal view returns (uint256[4] balances)
```

### _getTotalBalances

```solidity
function _getTotalBalances() internal view returns (uint256[4] balances)
```

Total balances including idle tokens + LP position amounts valued by strategies

### receive

```solidity
receive() external payable
```

