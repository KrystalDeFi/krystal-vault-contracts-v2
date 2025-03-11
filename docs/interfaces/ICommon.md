# Solidity API

## ICommon

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
  enum ICommon.AssetType assetType;
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
  uint256 principalTokenAmount;
}
```

### Instruction

```solidity
struct Instruction {
  uint8 instructionType;
  bytes params;
  bytes abiEncodedUserOrder;
  bytes orderSignature;
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

