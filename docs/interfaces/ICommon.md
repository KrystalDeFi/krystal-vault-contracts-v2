# Solidity API

## ICommon

### VaultConfig

```solidity
struct VaultConfig {
  bool allowDeposit;
  uint8 rangeStrategyType;
  uint8 tvlStrategyType;
  address[] supportedAddresses;
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
  struct ICommon.VaultConfig config;
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

### InvalidVaultConfig

```solidity
error InvalidVaultConfig()
```

### InvalidStrategy

```solidity
error InvalidStrategy()
```

### InvalidSwapRouter

```solidity
error InvalidSwapRouter()
```

