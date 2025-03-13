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
  address principleToken;
  uint256 principleTokenAmount;
  uint256 principleTokenAmountMin;
  bool allowDeposit;
  address[] supportedTokens;
}
```

### Instruction

```solidity
struct Instruction {
  uint8 instructionType;
  bytes params;
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

### InvalidSwapRouter

```solidity
error InvalidSwapRouter()
```

