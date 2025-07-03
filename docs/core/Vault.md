# Solidity API

## Vault

### SHARES_PRECISION

```solidity
uint256 SHARES_PRECISION
```

### WITHDRAWAL_FEE

```solidity
uint16 WITHDRAWAL_FEE
```

### ADMIN_ROLE_HASH

```solidity
bytes32 ADMIN_ROLE_HASH
```

### configManager

```solidity
contract IConfigManager configManager
```

### vaultOwner

```solidity
address vaultOwner
```

### vaultOwnerFeeBasisPoint

```solidity
uint16 vaultOwnerFeeBasisPoint
```

### operator

```solidity
address operator
```

### WETH

```solidity
address WETH
```

### vaultFactory

```solidity
address vaultFactory
```

### lastAllocateBlockNumber

```solidity
uint256 lastAllocateBlockNumber
```

### onlyOperator

```solidity
modifier onlyOperator()
```

### onlyAdminOrAutomator

```solidity
modifier onlyAdminOrAutomator()
```

### onlyPrivateVault

```solidity
modifier onlyPrivateVault()
```

### whenNotPaused

```solidity
modifier whenNotPaused()
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _operator, address _configManager, address _weth) public
```

Initializes the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |
| _owner | address | Owner of the vault |
| _operator | address | Address of the operator |
| _configManager | address | Address of the whitelist manager |
| _weth | address | Address of the WETH token |

### deposit

```solidity
function deposit(uint256 principalAmount, uint256 minShares) external payable returns (uint256 shares)
```

Deposits the asset to the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| principalAmount | uint256 | Amount of in principalToken |
| minShares | uint256 | Minimum amount of shares to mint |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares minted |

### depositPrincipal

```solidity
function depositPrincipal(uint256 principalAmount) external payable returns (uint256 shares)
```

Deposits principal tokens for private vaults

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| principalAmount | uint256 | Amount of principal tokens to deposit |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares minted |

### withdraw

```solidity
function withdraw(uint256 shares, bool unwrap, uint256 minReturnAmount) external returns (uint256 returnAmount)
```

Withdraws the asset as principal token from the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Amount of shares to be burned |
| unwrap | bool | Unwrap WETH to ETH |
| minReturnAmount | uint256 | Minimum amount of principal token to return |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAmount | uint256 | Amount of principal token returned |

### withdrawPrincipal

```solidity
function withdrawPrincipal(uint256 amount, bool unwrap) external returns (uint256)
```

Withdraws principal tokens (not from strategies) for private vaults

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount of principal tokens to withdraw |
| unwrap | bool | Unwrap WETH to ETH |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | returnAmount Amount of principal tokens returned |

### allocate

```solidity
function allocate(struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint64 gasFeeX64, bytes data) external
```

Allocates un-used assets to the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputAssets | struct AssetLib.Asset[] | Input assets to allocate |
| strategy | contract IStrategy | Strategy to allocate to |
| gasFeeX64 | uint64 | Gas fee with X64 precision |
| data | bytes | Data for the strategy |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, uint256 amountTokenOutMin) external returns (struct AssetLib.Asset[] harvestedAssets)
```

Harvests the assets from the strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | Asset to harvest |
| amountTokenOutMin | uint256 | The minimum amount out by tokenOut |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| harvestedAssets | struct AssetLib.Asset[] | Harvested assets |

### harvestPrivate

```solidity
function harvestPrivate(struct AssetLib.Asset[] assets, bool unwrap, uint256 amountTokenOutMin) external
```

Harvests rewards from a strategy asset and sends to vaultOwner (private vault only)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | Assets to harvest |
| unwrap | bool | Unwrap WETH to ETH |
| amountTokenOutMin | uint256 | Minimum amount out by tokenOut |

### _harvest

```solidity
function _harvest(struct AssetLib.Asset asset, uint256 amountTokenOutMin) internal returns (struct AssetLib.Asset[] harvestedAssets)
```

_Harvests the assets from the strategy_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | Asset to harvest |
| amountTokenOutMin | uint256 | The minimum amount out by tokenOut |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| harvestedAssets | struct AssetLib.Asset[] | Harvested assets |

### getTotalValue

```solidity
function getTotalValue() public view returns (uint256 totalValue)
```

Returns the total value of the vault

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| totalValue | uint256 | Total value of the vault in principal token |

### sweepToken

```solidity
function sweepToken(address[] tokens) external
```

Sweeps the tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokens | address[] | Tokens to sweep |

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
function sweepERC1155(address[] _tokens, uint256[] _tokenIds) external
```

Sweep ERC1155 tokens to the caller

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _tokens | address[] | Tokens to sweep |
| _tokenIds | uint256[] | Token IDs to sweep |

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

### allowDeposit

```solidity
function allowDeposit(struct ICommon.VaultConfig _config, uint16 _vaultOwnerFeeBasisPoint) external
```

Turn on allow deposit

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _config | struct ICommon.VaultConfig | New vault config |
| _vaultOwnerFeeBasisPoint | uint16 | Vault owner fee basis point |

### _addAssets

```solidity
function _addAssets(struct AssetLib.Asset[] newAssets) internal
```

_Adds multiple assets to the vault_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newAssets | struct AssetLib.Asset[] | New assets to add |

### getInventory

```solidity
function getInventory() external view returns (struct AssetLib.Asset[] assets)
```

Returns the vault's inventory

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | Array of assets in the vault |

### getVaultConfig

```solidity
function getVaultConfig() external view returns (bool isAllowDeposit, uint8 rangeStrategyType, uint8 tvlStrategyType, address principalToken, address[] supportedAddresses, uint16 _vaultOwnerFeeBasisPoint)
```

Returns the vault's config

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| isAllowDeposit | bool | Allow deposit |
| rangeStrategyType | uint8 | Range strategy type |
| tvlStrategyType | uint8 | TVL strategy type |
| principalToken | address | Principal token address |
| supportedAddresses | address[] | Supported addresses |
| _vaultOwnerFeeBasisPoint | uint16 | Vault owner fee basis point |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

### receive

```solidity
receive() external payable
```

### decimals

```solidity
function decimals() public view returns (uint8)
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

### _delegateCallToStrategy

```solidity
function _delegateCallToStrategy(address strategy, bytes cData) internal returns (bytes returnData)
```

