# Solidity API

## RamsesFarmingStrategy

Claims the RAM vault positions earn in Ramses CL gauges. Ramses gauges are non-custodial: a position earns
        while the vault holds it, so there is nothing to stake or unstake, only rewards to claim through the
        position manager.

### nfpm

```solidity
address nfpm
```

The Ramses CL position manager, read from the Voter at deployment

### rewardToken

```solidity
address rewardToken
```

RAM: the token Ramses gauges pay emissions in

### configManager

```solidity
contract IPrivateConfigManager configManager
```

### RamsesFarmingRewardsHarvested

```solidity
event RamsesFarmingRewardsHarvested(uint256 tokenId, address nfpm, uint256 claimedAmount, uint256 harvestedAmount, address msgSender)
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenId | uint256 |  |
| nfpm | address |  |
| claimedAmount | uint256 | The RAM the claim brought in, before fees |
| harvestedAmount | uint256 | What is left after fees: kept by the vault, or sent to the vault owner |
| msgSender | address |  |

### constructor

```solidity
constructor(address _voter, address _configManager) public
```

### harvest

```solidity
function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) external payable
```

Claim the position's RAM, take the fees and optionally forward the rest to the vault owner.

_Reverts when the position's pool has no gauge. Claims RAM only: xRAM can't be transferred out of the vault.
     Measures what arrived, so a claim the gauge forfeits (made too soon after a liquidity change, or flagged by
     Ramses' reward validator) yields nothing and charges nothing instead of reverting._

### _handleReward

```solidity
function _handleReward(uint256 claimedAmount, uint64 rewardFeeX64, uint64 gasFeeX64) internal returns (uint256 harvestedAmount)
```

