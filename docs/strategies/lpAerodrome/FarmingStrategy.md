# Solidity API

## FarmingStrategy

Strategy for farming Aerodrome LP positions using composition with LpStrategy

_Uses composition to delegate LP operations to LpStrategy while adding farming capabilities_

### Q64

```solidity
uint256 Q64
```

### lpStrategyImplementation

```solidity
address lpStrategyImplementation
```

### configManager

```solidity
contract IConfigManager configManager
```

### rewardSwapper

```solidity
contract RewardSwapper rewardSwapper
```

### validator

```solidity
contract IFarmingStrategyValidator validator
```

### constructor

```solidity
constructor(address _lpStrategyImplementation, address _configManager, address _rewardSwapper, address _validator) public
```

Constructor

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _lpStrategyImplementation | address | Address of the LpStrategy implementation for delegatecall |
| _configManager | address | Address of the config manager |
| _rewardSwapper | address | Address of the reward swapper contract |
| _validator | address | Address of the farming strategy validator |

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset, address principalToken) external view returns (uint256)
```

Calculate the value of a farming position including LP value and pending rewards

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The farming asset |
| principalToken | address | The principal token to value against |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The total value in principal token terms |

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes data) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Convert assets with farming operations

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | Input assets |
| config | struct ICommon.VaultConfig | Vault configuration |
| feeConfig | struct ICommon.FeeConfig | Fee configuration |
| data | bytes | Encoded farming instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Output assets |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut, uint256 amountTokenOutMin, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Harvest both LP fees and farming rewards

_Reverts if LP harvesting fails or minimum output not met_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The farming asset |
| tokenOut | address | Desired output token |
| amountTokenOutMin | uint256 | Minimum output amount |
| vaultConfig | struct ICommon.VaultConfig | Vault configuration |
| feeConfig | struct ICommon.FeeConfig | Fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Combined harvest results |

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig config) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Convert principal token to farmed LP position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | Existing asset (contains farming parameters in strategy field) |
| principalTokenAmount | uint256 | Amount of principal token to convert |
| config | struct ICommon.VaultConfig | Vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Array containing the farmed LP position |

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Convert farmed LP position to principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The farmed LP asset |
| shares | uint256 | Number of shares to convert |
| totalSupply | uint256 | Total supply of shares |
| config | struct ICommon.VaultConfig | Vault configuration |
| feeConfig | struct ICommon.FeeConfig | Fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Array containing principal token assets |

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external view
```

Validate farming asset

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to validate |
| config | struct ICommon.VaultConfig | Vault configuration |

### _getDepositedGauge

```solidity
function _getDepositedGauge(struct AssetLib.Asset asset) internal view returns (address gauge)
```

Check if an asset represents a deposited position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| gauge | address | The gauge address if deposited, address(0) if not deposited |

### _isDeposited

```solidity
function _isDeposited(struct AssetLib.Asset asset) internal view returns (bool isDeposited)
```

Check if an asset represents a deposited position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| isDeposited | bool | True if position is deposited in farming |

### _isRegularLP

```solidity
function _isRegularLP(struct AssetLib.Asset asset) internal view returns (bool isLP)
```

Check if an asset represents a regular LP position (not deposited)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| isLP | bool | True if it's a regular LP position |

### _getNFTContract

```solidity
function _getNFTContract(struct AssetLib.Asset asset) internal view returns (address nftContract)
```

Get the NFT contract address for an asset

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to get NFT contract for |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| nftContract | address | The NFT contract address |

### _depositExistingLP

```solidity
function _depositExistingLP(struct AssetLib.Asset[] assets, struct IFarmingStrategy.DepositExistingLPParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

Deposit existing LP NFT into farming

### _createAndDepositLP

```solidity
function _createAndDepositLP(struct AssetLib.Asset[] assets, struct IFarmingStrategy.CreateAndDepositLPParams params, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Create LP position and deposit it into farming

### _withdrawLP

```solidity
function _withdrawLP(struct AssetLib.Asset[] assets, struct IFarmingStrategy.WithdrawLPParams params, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Withdraw LP position from farming

### _withdrawLPToPrincipal

```solidity
function _withdrawLPToPrincipal(struct AssetLib.Asset[] assets, struct IFarmingStrategy.WithdrawLPToPrincipalParams params, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Withdraw LP position from farming to principal, if position still has liquidity, deposit into farming again

### _rebalanceAndDeposit

```solidity
function _rebalanceAndDeposit(struct AssetLib.Asset[] assets, struct IFarmingStrategy.RebalanceAndDepositParams params, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Rebalance LP position while maintaining farming deposit

### _depositPosition

```solidity
function _depositPosition(struct AssetLib.Asset lpAsset, address gauge) internal returns (struct AssetLib.Asset farmingAsset)
```

Deposit a position into the specified gauge

### _withdrawPosition

```solidity
function _withdrawPosition(struct AssetLib.Asset farmingAsset) internal returns (struct AssetLib.Asset lpAsset)
```

Withdraw a position from the specified gauge

### _harvestFarmingRewards

```solidity
function _harvestFarmingRewards(struct AssetLib.Asset asset, address tokenOut, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Harvest farming rewards from a specific gauge

### _combineHarvestResults

```solidity
function _combineHarvestResults(struct AssetLib.Asset[] lpResults, struct AssetLib.Asset[] farmingResults, struct AssetLib.Asset farmingAsset) internal pure returns (struct AssetLib.Asset[] combined)
```

Combine LP and farming harvest results

### _swapRewardToken

```solidity
function _swapRewardToken(address rewardToken, address tokenOut, uint256 amount) internal returns (uint256 amountOut)
```

Swap reward token to desired output token

_Reverts if reward token is not supported or swap fails_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| rewardToken | address | The reward token to swap from |
| tokenOut | address | The desired output token |
| amount | uint256 | The amount of reward token to swap |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | The amount of output token received |

### _takeFees

```solidity
function _takeFees(address token, uint256 amount, struct ICommon.FeeConfig feeConfig) internal returns (uint256 totalFeeAmount)
```

Take fees from harvested rewards

### _delegateToLpStrategy

```solidity
function _delegateToLpStrategy(bytes callData) internal returns (bytes result)
```

Generic delegatecall helper for LpStrategy interactions

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| callData | bytes | The encoded function call data |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| result | bytes | The returned data from the delegatecall |

### _lpConvert

```solidity
function _lpConvert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes data) internal returns (struct AssetLib.Asset[] returnAssets)
```

Delegatecall to LpStrategy.convert()

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | Input assets |
| config | struct ICommon.VaultConfig | Vault configuration |
| feeConfig | struct ICommon.FeeConfig | Fee configuration |
| data | bytes | Instruction data |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Output assets |

### _lpHarvest

```solidity
function _lpHarvest(struct AssetLib.Asset asset, address tokenOut, uint256 amountTokenOutMin, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Delegatecall to LpStrategy.harvest()

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to harvest |
| tokenOut | address | Desired output token |
| amountTokenOutMin | uint256 | Minimum output amount |
| vaultConfig | struct ICommon.VaultConfig | Vault configuration |
| feeConfig | struct ICommon.FeeConfig | Fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Harvest results |

### _lpConvertToPrincipal

```solidity
function _lpConvertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Delegatecall to LpStrategy.convertToPrincipal()

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | Existing asset |
| shares | uint256 | Number of shares |
| totalSupply | uint256 | Total supply |
| config | struct ICommon.VaultConfig | Vault configuration |
| feeConfig | struct ICommon.FeeConfig | Fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | Conversion results |

### _lpConvertFromPrincipal

```solidity
function _lpConvertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _lpRevalidate

```solidity
function _lpRevalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) internal view
```

Delegatecall to LpStrategy.revalidate()

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | Asset to validate |
| config | struct ICommon.VaultConfig | Vault configuration |

### onERC721Received

```solidity
function onERC721Received(address operator, address from, uint256 tokenId, bytes data) external pure returns (bytes4)
```

Handle receiving NFTs

### receive

```solidity
receive() external payable
```

Receive ETH

