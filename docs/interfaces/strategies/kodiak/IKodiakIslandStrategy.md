# Solidity API

## IKodiakIslandStrategy

### InvalidAssetStrategy

```solidity
error InvalidAssetStrategy()
```

### InvalidPrincipalToken

```solidity
error InvalidPrincipalToken()
```

### InvalidRewardVault

```solidity
error InvalidRewardVault()
```

### SwapAndStakeParams

```solidity
struct SwapAndStakeParams {
  address kodiakIslandLpAddress;
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

