# Solidity API

## ICLGauge

### nft

```solidity
function nft() external view returns (address)
```

NonfungiblePositionManager used to create nfts this gauge accepts

### voter

```solidity
function voter() external view returns (address)
```

Voter contract gauge receives emissions from

### pool

```solidity
function pool() external view returns (address)
```

Address of the CL pool linked to the gauge

### gaugeFactory

```solidity
function gaugeFactory() external view returns (address)
```

Address of the factory that created this gauge

### feesVotingReward

```solidity
function feesVotingReward() external view returns (address)
```

Address of the FeesVotingReward contract linked to the gauge

### periodFinish

```solidity
function periodFinish() external view returns (uint256)
```

Timestamp end of current rewards period

### rewardRate

```solidity
function rewardRate() external view returns (uint256)
```

Current reward rate of rewardToken to distribute per second

### rewards

```solidity
function rewards(uint256 tokenId) external view returns (uint256)
```

Claimable rewards by tokenId

### lastUpdateTime

```solidity
function lastUpdateTime(uint256 tokenId) external view returns (uint256)
```

Most recent timestamp tokenId called updateRewards

### rewardRateByEpoch

```solidity
function rewardRateByEpoch(uint256) external view returns (uint256)
```

View to see the rewardRate given the timestamp of the start of the epoch

### fees0

```solidity
function fees0() external view returns (uint256)
```

Cached amount of fees generated from the Pool linked to the Gauge of token0

### fees1

```solidity
function fees1() external view returns (uint256)
```

Cached amount of fees generated from the Pool linked to the Gauge of token1

### WETH9

```solidity
function WETH9() external view returns (address)
```

Cached address of WETH9

### token0

```solidity
function token0() external view returns (address)
```

Cached address of token0, corresponding to token0 of the pool

### token1

```solidity
function token1() external view returns (address)
```

Cached address of token1, corresponding to token1 of the pool

### tickSpacing

```solidity
function tickSpacing() external view returns (int24)
```

Cached tick spacing of the pool.

### left

```solidity
function left() external view returns (uint256 _left)
```

Total amount of rewardToken to distribute for the current rewards period

### rewardToken

```solidity
function rewardToken() external view returns (address)
```

Address of the emissions token

### isPool

```solidity
function isPool() external view returns (bool)
```

To provide compatibility support with the old voter

### supportsPayable

```solidity
function supportsPayable() external view returns (bool)
```

Checks whether the gauge supports payments in Native tokens

### rewardGrowthInside

```solidity
function rewardGrowthInside(uint256 tokenId) external view returns (uint256)
```

Returns the rewardGrowthInside of the position at the last user action (deposit, withdraw, getReward)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenId | uint256 | The tokenId of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The rewardGrowthInside for the position |

### initialize

```solidity
function initialize(address _pool, address _feesVotingReward, address _rewardToken, address _voter, address _nft, address _token0, address _token1, int24 _tickSpacing, bool _isPool) external
```

Called on gauge creation by CLGaugeFactory

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _pool | address | The address of the pool |
| _feesVotingReward | address | The address of the feesVotingReward contract |
| _rewardToken | address | The address of the reward token |
| _voter | address | The address of the voter contract |
| _nft | address | The address of the nft position manager contract |
| _token0 | address | The address of token0 of the pool |
| _token1 | address | The address of token1 of the pool |
| _tickSpacing | int24 | The tick spacing of the pool |
| _isPool | bool | Whether the attached pool is a real pool or not |

### earned

```solidity
function earned(address account, uint256 tokenId) external view returns (uint256)
```

Returns the claimable rewards for a given account and tokenId

_Throws if account is not the position owner
pool.updateRewardsGrowthGlobal() needs to be called first, to return the correct claimable rewards_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| account | address | The address of the user |
| tokenId | uint256 | The tokenId of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of claimable reward |

### getReward

```solidity
function getReward(address account) external
```

Retrieve rewards for all tokens owned by an account

_Throws if not called by the voter_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| account | address | The account of the user |

### getReward

```solidity
function getReward(uint256 tokenId) external
```

Retrieve rewards for a tokenId

_Throws if not called by the position owner_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenId | uint256 | The tokenId of the position |

### notifyRewardAmount

```solidity
function notifyRewardAmount(uint256 amount) external
```

Notifies gauge of gauge rewards.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount of gauge rewards (emissions) to notify. Must be greater than 604_800. |

### notifyRewardWithoutClaim

```solidity
function notifyRewardWithoutClaim(uint256 amount) external
```

_Notifies gauge of gauge rewards without distributing its fees.
     Assumes gauge reward tokens is 18 decimals.
     If not 18 decimals, rewardRate may have rounding issues._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount of gauge rewards (emissions) to notify. Must be greater than 604_800. |

### deposit

```solidity
function deposit(uint256 tokenId) external
```

Used to deposit a CL position into the gauge
Allows the user to receive emissions instead of fees

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenId | uint256 | The tokenId of the position |

### withdraw

```solidity
function withdraw(uint256 tokenId) external
```

Used to withdraw a CL position from the gauge
Allows the user to receive fees instead of emissions
Outstanding emissions will be collected on withdrawal

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenId | uint256 | The tokenId of the position |

### stakedValues

```solidity
function stakedValues(address depositor) external view returns (uint256[])
```

Fetch all tokenIds staked by a given account

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address of the user |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256[] | The tokenIds of the staked positions |

### stakedByIndex

```solidity
function stakedByIndex(address depositor, uint256 index) external view returns (uint256)
```

Fetch a staked tokenId by index

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address of the user |
| index | uint256 | The index of the staked tokenId |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The tokenId of the staked position |

### stakedContains

```solidity
function stakedContains(address depositor, uint256 tokenId) external view returns (bool)
```

Check whether a position is staked in the gauge by a certain user

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address of the user |
| tokenId | uint256 | The tokenId of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Whether the position is staked in the gauge |

### stakedLength

```solidity
function stakedLength(address depositor) external view returns (uint256)
```

The amount of positions staked in the gauge by a certain user

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address of the user |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of positions staked in the gauge |

