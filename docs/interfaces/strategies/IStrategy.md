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
function valueOf(struct AssetLib.Asset asset, address principalToken) external returns (uint256)
```

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, bytes data) external returns (struct AssetLib.Asset[])
```

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut) external returns (struct AssetLib.Asset[])
```

### getUnderlyingAssets

```solidity
function getUnderlyingAssets(struct AssetLib.Asset asset) external returns (struct AssetLib.Asset[])
```

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig config) external returns (struct AssetLib.Asset[])
```

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config) external returns (struct AssetLib.Asset[])
```

