# Solidity API

## CollectFee

### FARM_REWARD_FEE_TYPE

```solidity
uint8 FARM_REWARD_FEE_TYPE
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
event FeeCollect(address token, uint256 feeAmount, uint16 feeBps, uint8 feeType, address sender, address recipient)
```

### collect

```solidity
function collect(address recipient, address token, uint256 amount, uint16 feeBps, uint8 feeType) internal returns (uint256 feeAmount)
```

