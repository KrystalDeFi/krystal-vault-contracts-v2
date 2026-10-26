# Solidity API

## AerodromeFarmingStrategy

Stakes vault positions in the CL gauges of one gauge factory: a legacy Aerodrome/Velodrome Slipstream
        one, or Aero's (the merged Aerodrome + Velodrome protocol), whose gauges pay emissions through
        `claimEmissions` instead of `getReward`.

### gaugeFactory

```solidity
address gaugeFactory
```

### nfpm

```solidity
address nfpm
```

### configManager

```solidity
contract IPrivateConfigManager configManager
```

### leafVoter

```solidity
address leafVoter
```

Aero's LeafVoter when the gauge factory is Aero's, zero for a legacy gauge factory

### emissionToken

```solidity
address emissionToken
```

Token Aero gauges pay emissions in on this chain: AERO on Base, xAERO on the other chains, read from the
        LeafVoter at deployment. Zero for a legacy gauge factory, whose gauges report their reward token themselves.

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
constructor(address _gaugeFactory, address _configManager) public
```

_A legacy gauge factory is told apart from Aero's by not having `leafVoter()`._

### _getGaugeFromTokenId

```solidity
function _getGaugeFromTokenId(uint256 tokenId) internal view returns (address gauge)
```

### deposit

```solidity
function deposit(uint256 tokenId) external payable
```

### withdraw

```solidity
function withdraw(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) external payable
```

### emergencyWithdraw

```solidity
function emergencyWithdraw(uint256 tokenId) external payable
```

Aero only: unstake through the gauge's emergency exit, which works only while Aero governance has it
        enabled. The position's accrued emissions are forfeited.

### harvest

```solidity
function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) external payable
```

### _harvest

```solidity
function _harvest(address clGauge, uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) internal returns (uint256 harvestedAmount)
```

### _distributeReward

```solidity
function _distributeReward(address rewardToken, uint256 balanceBefore, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) internal returns (uint256 harvestedAmount)
```

_Takes the fees from what the claim paid, then forwards the rest to the vault owner when asked to._

### _handleReward

```solidity
function _handleReward(address rewardToken, uint256 balanceBefore, uint64 rewardFeeX64, uint64 gasFeeX64) internal returns (uint256 harvestedAmount)
```

