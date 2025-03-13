# Solidity API

## IVault

### Deposit

```solidity
event Deposit(address account, uint256 shares)
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

### SetAllowDeposit

```solidity
event SetAllowDeposit(bool _allowDeposit)
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

### vaultOwner

```solidity
function vaultOwner() external view returns (address)
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _whitelistManager, address _vaultAutomator) external
```

### deposit

```solidity
function deposit(uint256 shares) external returns (uint256 returnShares)
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

### setAllowDeposit

```solidity
function setAllowDeposit(bool _allowDeposit) external
```

