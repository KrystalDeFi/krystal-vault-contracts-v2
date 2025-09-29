# Solidity API

## ILpChainingStrategy

### StrategyDelegateCallFailed

```solidity
error StrategyDelegateCallFailed()
```

### ChainingInstructionType

```solidity
enum ChainingInstructionType {
  Batch,
  DecreaseAndBatch
}
```

### ChainingInstruction

```solidity
struct ChainingInstruction {
  enum ILpStrategy.InstructionType instructionType;
  address strategy;
  bytes params;
}
```

### ModifiedAddonPrincipalAmountParams

```solidity
struct ModifiedAddonPrincipalAmountParams {
  uint256 addonPrincipalAmount;
  bytes params;
}
```

