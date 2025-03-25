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

### FeeType

```solidity
enum FeeType {
  PLATFORM,
  OWNER,
  GAS
}
```

### FeeCollected

```solidity
event FeeCollected(enum IStrategy.FeeType feeType, address recipient, address token, uint256 amount)
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset, address principalToken) external view returns (uint256)
```

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes data) external returns (struct AssetLib.Asset[])
```

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut, struct ICommon.FeeConfig feeConfig) external returns (struct AssetLib.Asset[])
```

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig config) external returns (struct AssetLib.Asset[])
```

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) external returns (struct AssetLib.Asset[])
```

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external
```

