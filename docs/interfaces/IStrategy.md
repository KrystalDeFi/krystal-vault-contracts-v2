# Solidity API

## IStrategy

### DepositDetails

```solidity
struct DepositDetails {
  address token;
  uint256 tokenId;
  uint256 amount;
}
```

### deposit

```solidity
function deposit(uint256 amount, bytes data) external returns (struct IStrategy.DepositDetails)
```

### withdraw

```solidity
function withdraw(uint256 shares) external returns (uint256 amount)
```

### getValueInPrinciple

```solidity
function getValueInPrinciple(struct IStrategy.DepositDetails) external returns (uint256 amount)
```

