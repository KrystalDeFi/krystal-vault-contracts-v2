# Solidity API

## IStrategy

### InvalidAsset

```solidity
error InvalidAsset()
```

### InvalidNumberOfAssets

```solidity
error InvalidNumberOfAssets()
```

### InvalidInstructionType

```solidity
error InvalidInstructionType()
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset) external returns (struct AssetLib.Asset[] assets)
```

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, bytes data) external returns (struct AssetLib.Asset[])
```

### harvest

```solidity
function harvest(struct AssetLib.Asset asset) external returns (struct AssetLib.Asset[])
```

### getUnderlyingAssets

```solidity
function getUnderlyingAssets(struct AssetLib.Asset asset) external returns (struct AssetLib.Asset[])
```

### convertIntoExisting

```solidity
function convertIntoExisting(struct AssetLib.Asset existingAsset, struct AssetLib.Asset[] assets) external returns (struct AssetLib.Asset[])
```

