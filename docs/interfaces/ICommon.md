# Solidity API

## ICommon

### VaultConfig

```solidity
struct VaultConfig {
  bool allowDeposit;
  uint8 rangeStrategyType;
  uint8 tvlStrategyType;
  address principalToken;
  address[] supportedAddresses;
}
```

### VaultCreateParams

```solidity
struct VaultCreateParams {
  string name;
  string symbol;
  uint256 principalTokenAmount;
  struct ICommon.VaultConfig config;
}
```

### FeeConfig

```solidity
struct FeeConfig {
  uint16 vaultOwnerFeeBasisPoint;
  address vaultOwner;
  uint16 platformFeeBasisPoint;
  address platformFeeRecipient;
  uint16 gasFeeBasisPoint;
  address gasFeeRecipient;
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

### InvalidFeeConfig

```solidity
error InvalidFeeConfig()
```

### InvalidStrategy

```solidity
error InvalidStrategy()
```

### InvalidSwapRouter

```solidity
error InvalidSwapRouter()
```

### InvalidInstructionType

```solidity
error InvalidInstructionType()
```

