# Solidity API

## IMerklStrategy

### NotEnoughAmountOut

```solidity
error NotEnoughAmountOut()
```

### SwapFailed

```solidity
error SwapFailed()
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
  address swapRouter;
  bytes swapData;
  uint256 amountOutMin;
  uint32 deadline;
  bytes signature;
}
```

