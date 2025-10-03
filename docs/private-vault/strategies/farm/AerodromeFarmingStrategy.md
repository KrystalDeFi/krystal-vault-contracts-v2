# Solidity API

## AerodromeFarmingStrategy

### gaugeFactory

```solidity
address gaugeFactory
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

### deposit

```solidity
function deposit(uint256 tokenId, address clGauge) external
```

### withdraw

```solidity
function withdraw(uint256 tokenId, address clGauge) external
```

### harvest

```solidity
function harvest(address clGauge, uint256 tokenId) external
```

