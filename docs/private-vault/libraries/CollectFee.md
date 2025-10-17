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

### Q64

```solidity
uint256 Q64
```

### InvalidRewardFee

```solidity
error InvalidRewardFee()
```

### FeeRecipientNotSet

```solidity
error FeeRecipientNotSet()
```

### FeeCollect

```solidity
event FeeCollect(address token, uint256 feeAmount, uint64 rewardFeeX64, enum CollectFee.FeeType feeType, address sender, address recipient)
```

### collect

```solidity
function collect(address recipient, address token, uint256 amount, uint64 rewardFeeX64, enum CollectFee.FeeType feeType) internal returns (uint256 feeAmount)
```

