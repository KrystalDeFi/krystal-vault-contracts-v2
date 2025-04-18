# Solidity API

## IMerklStrategy

### NotEnoughAmountOut

```solidity
error NotEnoughAmountOut()
```

### InstructionType

```solidity
enum InstructionType {
  ClaimAndSwap
}
```

### ClaimAndSwapParams

```solidity
struct ClaimAndSwapParams {
  address distributor;
  address token;
  uint256 amount;
  bytes32[] proof;
  bytes swapData;
  uint256 amountOutMin;
}
```

