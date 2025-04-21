# Solidity API

## IFeeTaker

### FeeType

```solidity
enum FeeType {
  PLATFORM,
  OWNER,
  GAS
}
```

### FeeCollected

```solidity
event FeeCollected(enum IFeeTaker.FeeType feeType, address recipient, address token, uint256 amount)
```

