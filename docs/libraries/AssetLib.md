# Solidity API

## AssetLib

### AssetType

```solidity
enum AssetType {
  ERC20,
  ERC721,
  ERC1155
}
```

### Asset

```solidity
struct Asset {
  enum AssetLib.AssetType assetType;
  address strategy;
  address token;
  uint256 tokenId;
  uint256 amount;
}
```
