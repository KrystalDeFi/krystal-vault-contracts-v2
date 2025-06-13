# Solidity API

## IVaultStrategy

### PrincipalTokenMismatch

```solidity
error PrincipalTokenMismatch()
```

### InvalidVault

```solidity
error InvalidVault()
```

### InstructionType

```solidity
enum InstructionType {
  Deposit,
  Withdraw
}
```

### DepositParams

```solidity
struct DepositParams {
  address vault;
  uint256 principalAmount;
  uint256 minShares;
}
```

### WithdrawParams

```solidity
struct WithdrawParams {
  uint256 shares;
  bool unwrap;
  uint256 minReturnAmount;
}
```

