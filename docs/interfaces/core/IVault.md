# Solidity API

## IVault

### VaultDeposit

```solidity
event VaultDeposit(address vaultFactory, address account, uint256 principalAmount, uint256 shares)
```

### VaultDepositPrincipal

```solidity
event VaultDepositPrincipal(address vaultFactory, address owner, uint256 principalAmount, uint256 shares)
```

### VaultWithdraw

```solidity
event VaultWithdraw(address vaultFactory, address account, uint256 principalAmount, uint256 shares)
```

### VaultWithdrawPrincipal

```solidity
event VaultWithdrawPrincipal(address vaultFactory, address owner, uint256 principalAmount)
```

### VaultAllocate

```solidity
event VaultAllocate(address vaultFactory, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, struct AssetLib.Asset[] newAssets)
```

### VaultHarvest

```solidity
event VaultHarvest(address vaultFactory, struct AssetLib.Asset[] harvestedAssets)
```

### VaultHarvestPrivate

```solidity
event VaultHarvestPrivate(address vaultFactory, address owner, uint256 principalHarvestedAmount)
```

### SweepToken

```solidity
event SweepToken(address[] tokens)
```

### SweepERC721

```solidity
event SweepERC721(address[] _tokens, uint256[] _tokenIds)
```

### SweepERC1155

```solidity
event SweepERC1155(address[] _tokens, uint256[] _tokenIds, uint256[] _amounts)
```

### SetVaultConfig

```solidity
event SetVaultConfig(address vaultFactory, struct ICommon.VaultConfig config)
```

### VaultPaused

```solidity
error VaultPaused()
```

### InvalidAssetToken

```solidity
error InvalidAssetToken()
```

### InvalidAssetAmount

```solidity
error InvalidAssetAmount()
```

### InvalidSweepAsset

```solidity
error InvalidSweepAsset()
```

### InvalidAssetStrategy

```solidity
error InvalidAssetStrategy()
```

### InvalidAssetTokenId

```solidity
error InvalidAssetTokenId()
```

### InvalidAssetType

```solidity
error InvalidAssetType()
```

### DepositAllowed

```solidity
error DepositAllowed()
```

### DepositNotAllowed

```solidity
error DepositNotAllowed()
```

### MaxPositionsReached

```solidity
error MaxPositionsReached()
```

### InvalidShares

```solidity
error InvalidShares()
```

### Unauthorized

```solidity
error Unauthorized()
```

### InsufficientShares

```solidity
error InsufficientShares()
```

### FailedToSendEther

```solidity
error FailedToSendEther()
```

### InvalidWETH

```solidity
error InvalidWETH()
```

### InsufficientReturnAmount

```solidity
error InsufficientReturnAmount()
```

### ExceedMaxAllocatePerBlock

```solidity
error ExceedMaxAllocatePerBlock()
```

### vaultOwner

```solidity
function vaultOwner() external view returns (address)
```

### WETH

```solidity
function WETH() external view returns (address)
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _configManager, address _weth) external
```

### deposit

```solidity
function deposit(uint256 principalAmount, uint256 minShares) external payable returns (uint256 returnShares)
```

### withdraw

```solidity
function withdraw(uint256 shares, bool unwrap, uint256 minReturnAmount) external
```

### allocate

```solidity
function allocate(struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint64 gasFeeBasisPoint, bytes data) external
```

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, uint256 amountTokenOutMin) external
```

### harvestPrivate

```solidity
function harvestPrivate(struct AssetLib.Asset[] asset, bool unwrap, uint256 amountTokenOutMin) external
```

### getTotalValue

```solidity
function getTotalValue() external returns (uint256)
```

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

### sweepToken

```solidity
function sweepToken(address[] tokens) external
```

### sweepERC721

```solidity
function sweepERC721(address[] _tokens, uint256[] _tokenIds) external
```

### sweepERC1155

```solidity
function sweepERC1155(address[] _tokens, uint256[] _tokenIds, uint256[] _amounts) external
```

### allowDeposit

```solidity
function allowDeposit(struct ICommon.VaultConfig _config) external
```

### getInventory

```solidity
function getInventory() external view returns (struct AssetLib.Asset[] assets)
```

### getVaultConfig

```solidity
function getVaultConfig() external view returns (bool allowDeposit, uint8 rangeStrategyType, uint8 tvlStrategyType, address principalToken, address[] supportedAddresses)
```

