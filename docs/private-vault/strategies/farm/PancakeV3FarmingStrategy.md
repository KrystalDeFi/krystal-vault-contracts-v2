# Solidity API

## PancakeV3FarmingStrategy

### masterChefV3

```solidity
address masterChefV3
```

### configManager

```solidity
contract IPrivateConfigManager configManager
```

### PancakeV3FarmingStaked

```solidity
event PancakeV3FarmingStaked(address nfpm, uint256 tokenId, address masterChefV3, address msgSender)
```

### PancakeV3FarmingUnstaked

```solidity
event PancakeV3FarmingUnstaked(uint256 tokenId, address masterChefV3, address msgSender)
```

### PancakeV3FarmingRewardsHarvested

```solidity
event PancakeV3FarmingRewardsHarvested(uint256 tokenId, address masterChefV3, address msgSender)
```

### constructor

```solidity
constructor(address _masterChefV3, address _configManager) public
```

### deposit

```solidity
function deposit(uint256 tokenId) external
```

### withdraw

```solidity
function withdraw(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) external
```

### harvest

```solidity
function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) external
```

### _harvest

```solidity
function _harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal
```

### _handleReward

```solidity
function _handleReward(address rewardToken, uint256 balanceBefore, uint64 rewardFeeX64, uint64 gasFeeX64) internal
```

