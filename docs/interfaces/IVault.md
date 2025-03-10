# Solidity API

## IVault

### InvalidAssetAmount

```solidity
error InvalidAssetAmount()
```

### InvalidSweepAsset

```solidity
error InvalidSweepAsset()
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _whitelistManager, address _vaultAutomator, struct ICommon.Asset wrapAsset) external
```

### deposit

```solidity
function deposit(uint256 amount) external returns (uint256 shares)
```

### depositPrinciple

```solidity
function depositPrinciple(uint256 amount) external returns (uint256 shares)
```

### allocate

```solidity
function allocate(struct ICommon.Asset[] inputAssets, contract IStrategy strategy, bytes data) external
```

### deallocate

```solidity
function deallocate(contract IStrategy strategy, uint256 allocationAmount) external
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

