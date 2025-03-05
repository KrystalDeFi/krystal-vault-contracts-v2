# Solidity API

## Vault

### stratsAlloc

```solidity
mapping(address => struct IStrategy.DepositDetails) stratsAlloc
```

### strategies

```solidity
contract IStrategy[] strategies
```

### deposit

```solidity
function deposit(uint256 amount) external returns (uint256 shares)
```

### allocate

```solidity
function allocate(uint256 amount, contract IStrategy strategy, bytes data) external
```

### deallocate

```solidity
function deallocate(contract IStrategy strategy, uint256 allocationAmount) external
```

### getTotalValue

```solidity
function getTotalValue() external returns (uint256)
```

