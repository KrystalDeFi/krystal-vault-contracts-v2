# Solidity API

## IRewardVault

### factory

```solidity
function factory() external view returns (address)
```

### stakeToken

```solidity
function stakeToken() external view returns (address)
```

### rewardToken

```solidity
function rewardToken() external view returns (address)
```

### rewards

```solidity
function rewards(address account) external view returns (uint256)
```

### earned

```solidity
function earned(address account) external view returns (uint256)
```

### stake

```solidity
function stake(uint256 amount) external
```

### withdraw

```solidity
function withdraw(uint256 amount) external
```

### exit

```solidity
function exit(address recipient) external
```

### getReward

```solidity
function getReward(address account, address recipient) external returns (uint256)
```

