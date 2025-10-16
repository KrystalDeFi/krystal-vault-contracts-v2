# Solidity API

## CollectFee

### FeeType

```solidity
enum FeeType {
  PLATFORM,
  OWNER,
  GAS,
  FARM_REWARD
}
```

### BPS_DENOMINATOR

```solidity
uint256 BPS_DENOMINATOR
```

### InvalidFeeBps

```solidity
error InvalidFeeBps()
```

### FeeRecipientNotSet

```solidity
error FeeRecipientNotSet()
```

### FeeCollect

```solidity
event FeeCollect(address token, uint256 feeAmount, uint16 feeBps, enum CollectFee.FeeType feeType, address sender, address recipient)
```

### collect

```solidity
function collect(address recipient, address token, uint256 amount, uint16 feeBps, enum CollectFee.FeeType feeType) internal returns (uint256 feeAmount)
```

