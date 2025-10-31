# Solidity API

## KyberFairFlowStrategy

### uniswapV4KEMHook

```solidity
address uniswapV4KEMHook
```

### configManager

```solidity
contract IPrivateConfigManager configManager
```

### InvalidInputLength

```solidity
error InvalidInputLength()
```

### FairFlowRewardClaim

```solidity
event FairFlowRewardClaim(address hook, address token, uint256 amount)
```

### constructor

```solidity
constructor(address _uniswapV4KEMHook, address _configManager) public
```

### claimFairFlowReward

```solidity
function claimFairFlowReward(address token, uint256 amount, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) external payable
```

