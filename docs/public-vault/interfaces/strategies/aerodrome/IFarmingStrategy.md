# Solidity API

## IFarmingStrategy

### FarmingInstructionType

```solidity
enum FarmingInstructionType {
  DepositExistingLP,
  CreateAndDepositLP,
  WithdrawLP,
  WithdrawLPToPrincipal,
  RebalanceAndDeposit,
  CompoundAndDeposit,
  HarvestFarmingRewards
}
```

### DepositExistingLPParams

```solidity
struct DepositExistingLPParams {
  address gauge;
}
```

### CreateAndDepositLPParams

```solidity
struct CreateAndDepositLPParams {
  address gauge;
  struct IAerodromeLpStrategy.SwapAndMintPositionParams lpParams;
}
```

### WithdrawLPParams

```solidity
struct WithdrawLPParams {
  uint256 minPrincipalAmount;
}
```

### WithdrawLPToPrincipalParams

```solidity
struct WithdrawLPToPrincipalParams {
  struct IAerodromeLpStrategy.DecreaseLiquidityAndSwapParams decreaseAndSwapParams;
}
```

### RebalanceAndDepositParams

```solidity
struct RebalanceAndDepositParams {
  struct IAerodromeLpStrategy.SwapAndRebalancePositionParams rebalanceParams;
}
```

### HarvestFarmingRewardsParams

```solidity
struct HarvestFarmingRewardsParams {
  address gauge;
  uint256 tokenId;
  address swapRouter;
  bytes swapData;
  uint256 minAmountOut;
}
```

### CompoundAndDepositParams

```solidity
struct CompoundAndDepositParams {
  struct IAerodromeLpStrategy.SwapAndCompoundParams swapAndCompoundParams;
}
```

### AerodromeStaked

```solidity
event AerodromeStaked(address nfpm, uint256 tokenId, address gauge, address msgSender)
```

### AerodromeUnstaked

```solidity
event AerodromeUnstaked(address nfpm, uint256 tokenId, address gauge, address msgSender)
```

### FarmingRewardsHarvested

```solidity
event FarmingRewardsHarvested(address gauge, address rewardToken, uint256 amount, address principalToken, uint256 principalAmount)
```

### LPCreatedAndDeposited

```solidity
event LPCreatedAndDeposited(uint256 tokenId, address gauge, uint256 liquidity)
```

### InvalidFarmingInstructionType

```solidity
error InvalidFarmingInstructionType()
```

### InvalidGauge

```solidity
error InvalidGauge()
```

### InvalidNFT

```solidity
error InvalidNFT()
```

### NFTNotDeposited

```solidity
error NFTNotDeposited()
```

### NFTAlreadyDeposited

```solidity
error NFTAlreadyDeposited()
```

### GaugeNotFound

```solidity
error GaugeNotFound()
```

### DelegationFailed

```solidity
error DelegationFailed()
```

### UnsupportedRewardToken

```solidity
error UnsupportedRewardToken()
```

