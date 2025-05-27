# Solidity API

## IMerklDistributor

### claim

```solidity
function claim(address[] users, address[] tokens, uint256[] amounts, bytes32[][] proofs) external
```

## MerklStrategy

Strategy for handling Merkl rewards for LP positions

### Q64

```solidity
uint256 Q64
```

### MerklRewardsClaimed

```solidity
event MerklRewardsClaimed(address token, uint256 amount, address principalToken, uint256 principalAmount)
```

### constructor

```solidity
constructor(address _configManager) public
```

Constructor

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _configManager | address | Address of the config manager |

### valueOf

```solidity
function valueOf(struct AssetLib.Asset, address) external pure returns (uint256)
```

Cannot be calculated

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | 0 |

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes data) external payable returns (struct AssetLib.Asset[] returnAssets)
```

This function is used to claim Merkl rewwards, it does not convert any assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets passed must be an empty array |
| config | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |
| data | bytes | Additional data for the conversion |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The resulting assets after conversion |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut, uint256 amountTokenOutMin, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[])
```

Harvest rewards from an asset

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to harvest from |
| tokenOut | address | The token to receive as rewards |
| amountTokenOutMin | uint256 | The minimum amount of tokens to receive |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | The resulting assets after harvesting |

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig config) external payable returns (struct AssetLib.Asset[])
```

Convert principal token to strategy assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert from |
| principalTokenAmount | uint256 | The amount of principal token to convert |
| config | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | The resulting assets after conversion |

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[])
```

Convert strategy assets to principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert from |
| shares | uint256 | The number of shares to convert |
| totalSupply | uint256 | The total supply of shares |
| config | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | The resulting assets after conversion |

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external view
```

Validate that an asset can be used with this strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to validate |
| config | struct ICommon.VaultConfig | The vault configuration |

### _claimAndSwap

```solidity
function _claimAndSwap(struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes data) internal returns (struct AssetLib.Asset[] returnAssets)
```

Claim and swap rewards to principal if needed

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| config | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |
| data | bytes | ClaimAndSwapParams |

### _claim

```solidity
function _claim(address distributor, address token, uint256 amount, bytes32[] proofs) internal
```

### _swap

```solidity
function _swap(address tokenIn, uint256 amountIn, address swapRouter, bytes swapData) internal
```

### _safeApprove

```solidity
function _safeApprove(contract IERC20 token, address _spender, uint256 _value) internal
```

### _takeFee

```solidity
function _takeFee(address token, uint256 amount, struct ICommon.FeeConfig feeConfig) internal returns (uint256 totalFeeAmount)
```

### receive

```solidity
receive() external payable
```

Receive ETH

