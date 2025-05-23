# Solidity API

## RewardVault

### factory

```solidity
address factory
```

### stakeToken

```solidity
address stakeToken
```

### rewardToken

```solidity
address rewardToken
```

### rewardRate

```solidity
uint256 rewardRate
```

### lastUpdateTime

```solidity
uint256 lastUpdateTime
```

### rewardPerTokenStored

```solidity
uint256 rewardPerTokenStored
```

### periodFinish

```solidity
uint256 periodFinish
```

### rewardsDuration

```solidity
uint256 rewardsDuration
```

### rewards

```solidity
mapping(address => uint256) rewards
```

### userRewardPerTokenPaid

```solidity
mapping(address => uint256) userRewardPerTokenPaid
```

### balanceOf

```solidity
mapping(address => uint256) balanceOf
```

### RewardAdded

```solidity
event RewardAdded(uint256 reward)
```

### Staked

```solidity
event Staked(address user, uint256 amount)
```

### Withdrawn

```solidity
event Withdrawn(address user, uint256 amount)
```

### RewardPaid

```solidity
event RewardPaid(address user, uint256 reward)
```

### RewardsDurationUpdated

```solidity
event RewardsDurationUpdated(uint256 newDuration)
```

### constructor

```solidity
constructor(address _factory, address _stakeToken, address _rewardToken) public
```

### updateReward

```solidity
modifier updateReward(address account)
```

### lastTimeRewardApplicable

```solidity
function lastTimeRewardApplicable() public view returns (uint256)
```

### rewardPerToken

```solidity
function rewardPerToken() public view returns (uint256)
```

### earned

```solidity
function earned(address account) public view returns (uint256)
```

### totalSupply

```solidity
function totalSupply() public view returns (uint256)
```

### stake

```solidity
function stake(uint256 amount) external
```

### withdraw

```solidity
function withdraw(uint256 amount) public
```

### exit

```solidity
function exit(address recipient) external
```

### getReward

```solidity
function getReward(address account, address recipient) public returns (uint256)
```

### notifyRewardAmount

```solidity
function notifyRewardAmount(uint256 reward) external
```

### setRewardsDuration

```solidity
function setRewardsDuration(uint256 _rewardsDuration) external
```

