# Solidity API

## InventoryLib

### Inventory

```solidity
struct Inventory {
  struct AssetLib.Asset[] assets;
  mapping(address => mapping(uint256 => uint256)) assetIndex;
}
```

### addAsset

```solidity
function addAsset(struct InventoryLib.Inventory self, struct AssetLib.Asset asset) internal
```

### removeAsset

```solidity
function removeAsset(struct InventoryLib.Inventory self, struct AssetLib.Asset asset) internal
```

### getAsset

```solidity
function getAsset(struct InventoryLib.Inventory self, address token, uint256 tokenId) internal view returns (struct AssetLib.Asset)
```

### contains

```solidity
function contains(struct InventoryLib.Inventory self, address token, uint256 tokenId) internal view returns (bool)
```

