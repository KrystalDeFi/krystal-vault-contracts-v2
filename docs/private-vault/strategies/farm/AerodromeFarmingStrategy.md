# Solidity API

## AerodromeFarmingStrategy

### FARM_REWARD_FEE_TYPE

```solidity
uint8 FARM_REWARD_FEE_TYPE
```

### gaugeFactory

```solidity
address gaugeFactory
```

### nfpm

```solidity
address nfpm
```

### AerodromeFarmingStaked

```solidity
event AerodromeFarmingStaked(address nfpm, uint256 tokenId, address gauge, address msgSender)
```

### AerodromeFarmingUnstaked

```solidity
event AerodromeFarmingUnstaked(uint256 tokenId, address gauge, address msgSender)
```

### AerodromeFarmingRewardsHarvested

```solidity
event AerodromeFarmingRewardsHarvested(uint256 tokenId, address gauge, address msgSender)
```

### constructor

```solidity
constructor(address _gaugeFactory) public
```

### _getGaugeFromTokenId

```solidity
function _getGaugeFromTokenId(uint256 tokenId) internal view returns (address gauge)
```

### deposit

```solidity
function deposit(uint256 tokenId) external
```

### withdraw

```solidity
function withdraw(uint256 tokenId, uint16 feeBps) external
```

### harvest

```solidity
function harvest(uint256 tokenId, uint16 feeBps) external
```

### _collectRewards

```solidity
function _collectRewards(address clGauge, uint256 tokenId, uint16 feeBps) internal
```

### _handleReward

```solidity
function _handleReward(address rewardToken, uint256 balanceBefore, uint16 feeBps) internal
```

