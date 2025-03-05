# Solidity API

## LpStrategy

### router

```solidity
address router
```

### DepositParams

```solidity
struct DepositParams {
  uint256 tokenId;
}
```

### deposit

```solidity
function deposit(uint256 amount, bytes data) external returns (struct IStrategy.DepositDetails details)
```

### getValueInPrinciple

```solidity
function getValueInPrinciple(struct IStrategy.DepositDetails details) external returns (uint256)
```

### withdraw

```solidity
function withdraw(uint256 amount) external returns (uint256)
```

### compound

```solidity
function compound(uint256 value) external returns (uint256)
```

