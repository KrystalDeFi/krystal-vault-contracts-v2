# Solidity API

## IVault

### Deposit

```solidity
event Deposit(address account, uint256 shares)
```

### Withdraw

```solidity
event Withdraw(address account, uint256 shares)
```

### Allocate

```solidity
event Allocate(struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, struct AssetLib.Asset[] newAssets)
```

### Deallocate

```solidity
event Deallocate(struct AssetLib.Asset[] inputAssets, struct AssetLib.Asset[] returnedAssets)
```

### SweepToken

```solidity
event SweepToken(address[] tokens)
```

### SweepNFToken

```solidity
event SweepNFToken(address[] _tokens, uint256[] _tokenIds)
```

### SetVaultConfig

```solidity
event SetVaultConfig(struct ICommon.VaultConfig config)
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

### vaultOwner

```solidity
function vaultOwner() external view returns (address)
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _configManager) external
```

### deposit

```solidity
function deposit(uint256 principalAmount, uint256 minShares) external returns (uint256 returnShares)
```

### withdraw

```solidity
function withdraw(uint256 shares) external
```

### allocate

```solidity
function allocate(struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, bytes data) external
```

### deallocate

```solidity
function deallocate(address token, uint256 tokenId, uint256 amount, bytes data) external
```

### getTotalValue

```solidity
function getTotalValue() external returns (uint256)
```

### getAssetAllocations

```solidity
function getAssetAllocations() external returns (struct AssetLib.Asset[] assets)
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

### sweepNFTToken

```solidity
function sweepNFTToken(address[] _tokens, uint256[] _tokenIds) external
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

