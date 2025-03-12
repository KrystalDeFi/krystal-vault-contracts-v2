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
function valueOf(struct ICommon.Asset asset) external returns (struct ICommon.Asset[] assets)
```

### convert

```solidity
function convert(struct ICommon.Asset[] assets, bytes data) external returns (struct ICommon.Asset[])
```

### harvest

```solidity
function harvest(struct ICommon.Asset asset) external returns (struct ICommon.Asset[])
```

### getUnderlyingAssets

```solidity
function getUnderlyingAssets(struct ICommon.Asset asset) external returns (struct ICommon.Asset[])
```

### convertIntoExisting

```solidity
function convertIntoExisting(struct ICommon.Asset existingAsset, struct ICommon.Asset[] assets) external returns (struct ICommon.Asset[])
```
