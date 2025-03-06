# Solidity API

## IStrategy

### valueOf

```solidity
function valueOf(struct ICommon.Asset asset) external returns (uint256 value)
```

### convert

```solidity
function convert(struct ICommon.Asset[] assets, bytes data) external returns (struct ICommon.Asset[])
```

Converts the asset to another assets

### convertIntoExisting

```solidity
function convertIntoExisting(struct ICommon.Asset existingAsset, struct ICommon.Asset[] newAssets, bytes data) external returns (struct ICommon.Asset[] asset)
```

