# Solidity API

## ICommon

### VaultCreateParams

```solidity
struct VaultCreateParams {
  uint16 ownerFeeBasisPoint;
  string name;
  string symbol;
  address principalToken;
  uint256 principalTokenAmount;
  uint256 principalTokenAmountMin;
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

