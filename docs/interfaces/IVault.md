# Solidity API

## IVault

### Deposit

```solidity
event Deposit(address account, uint256 shares)
```

### Allocate

```solidity
event Allocate(struct ICommon.Asset[] inputAssets, contract IStrategy strategy, struct ICommon.Asset[] newAssets)
```

### Deallocate

```solidity
event Deallocate(struct ICommon.Asset[] inputAssets, struct ICommon.Asset[] returnedAssets)
```

### SweepToken

```solidity
event SweepToken(address[] tokens)
```

### SweepNFToken

```solidity
event SweepNFToken(address[] tokens, uint256[] tokenIds)
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

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _whitelistManager, address _vaultAutomator) external
```

### deposit

```solidity
function deposit(uint256 amount) external returns (uint256 shares)
```

### allocate

```solidity
function allocate(struct ICommon.Asset[] inputAssets, contract IStrategy strategy, bytes data) external
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
function getAssetAllocations() external returns (struct ICommon.Asset[] assets, uint256[] values)
```

### sweepToken

```solidity
function sweepToken(address[] tokens) external
```

### sweepNFToken

```solidity
function sweepNFToken(address[] tokens, uint256[] tokenIds) external
```

