# Solidity API

## ICommon

### Asset

```solidity
struct Asset {
  address strategy;
  address token;
  uint256 tokenId;
  uint256 amount;
}
```

### VaultCreateParams

```solidity
struct VaultCreateParams {
  uint16 ownerFeeBasisPoint;
  string name;
  string symbol;
  address principalToken;
  struct ICommon.Asset[] assets;
}
```

### ZeroAddress

```solidity
error ZeroAddress()
```

### TransferFailed

```solidity
error TransferFailed()
```

### InvalidStrategy

```solidity
error InvalidStrategy()
```

