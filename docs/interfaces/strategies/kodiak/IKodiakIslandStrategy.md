# Solidity API

## IKodiakIslandStrategy

### InvalidAssetStrategy

```solidity
error InvalidAssetStrategy()
```

### InvalidIslandFactory

```solidity
error InvalidIslandFactory()
```

### InvalidPrincipalToken

```solidity
error InvalidPrincipalToken()
```

### SwapAndStakeParams

```solidity
struct SwapAndStakeParams {
  address bgtRewardVault;
}
```

### WithdrawAndSwapParams

```solidity
struct WithdrawAndSwapParams {
  uint256 minPrincipalAmount;
}
```

### InstructionType

```solidity
enum InstructionType {
  SwapAndStake,
  WithdrawAndSwap
}
```

