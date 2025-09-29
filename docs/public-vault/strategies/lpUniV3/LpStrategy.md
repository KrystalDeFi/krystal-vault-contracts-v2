# Solidity API

## LpStrategy

### Q64

```solidity
uint256 Q64
```

### Q96

```solidity
uint256 Q96
```

### Q128

```solidity
uint256 Q128
```

### Q192

```solidity
uint256 Q192
```

### configManager

```solidity
contract IConfigManager configManager
```

### optimalSwapper

```solidity
contract IOptimalSwapper optimalSwapper
```

### validator

```solidity
contract ILpValidator validator
```

### constructor

```solidity
constructor(address _configManager, address _optimalSwapper, address _validator, address _lpFeeTaker) public
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset, address principalToken) external view returns (uint256 valueInPrincipal)
```

Get value of the asset in terms of principalToken

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to get the value |
| principalToken | address | The principal token |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valueInPrincipal | uint256 | The value of the asset in terms of principalToken |

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig, bytes data) external payable returns (struct AssetLib.Asset[] returnAssets)
```

Converts the asset to another assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to convert |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |
| data | bytes | The data for the instruction |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address tokenOut, uint256 amountTokenOutMin, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[])
```

Harvest the asset fee

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to harvest |
| tokenOut | address | The token to swap to |
| amountTokenOutMin | uint256 | The minimum amount out by tokenOut |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | returnAssets The assets that were returned to the msg.sender |

### _harvest

```solidity
function _harvest(struct AssetLib.Asset asset, address tokenOut, uint256 amountTokenOutMin, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

_Harvest the asset fee_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to harvest |
| tokenOut | address | The token to swap to |
| amountTokenOutMin | uint256 | The minimum amount out by tokenOut |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig vaultConfig) external payable returns (struct AssetLib.Asset[])
```

convert the asset from the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert |
| principalTokenAmount | uint256 | The amount of principal token |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct AssetLib.Asset[] | returnAssets The assets that were returned to the msg.sender |

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

convert the asset to the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| existingAsset | struct AssetLib.Asset | The existing asset to convert |
| shares | uint256 | The shares to convert |
| totalSupply | uint256 | The total supply of the shares |
| config | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### swapAndMintPosition

```solidity
function swapAndMintPosition(struct AssetLib.Asset[] assets, struct ILpStrategy.SwapAndMintPositionParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Swaps the principal token to the other token and mints a new position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to swap and mint, assets[0] = principalToken |
| params | struct ILpStrategy.SwapAndMintPositionParams | The parameters for swapping and minting the position |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _mintPosition

```solidity
function _mintPosition(struct ICommon.VaultConfig vaultConfig, struct AssetLib.Asset[] assets, struct ILpStrategy.MintPositionParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

mints a new position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| assets | struct AssetLib.Asset[] | The assets to mint the position, assets[0] = token0, assets[1] = token1 |
| params | struct ILpStrategy.MintPositionParams | The parameters for minting the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### swapAndIncreaseLiquidity

```solidity
function swapAndIncreaseLiquidity(struct AssetLib.Asset[] assets, struct ILpStrategy.SwapAndIncreaseLiquidityParams params, struct ICommon.VaultConfig vaultConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Swaps the principal token to the other token and increases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to swap and increase liquidity, assets[2] = lpAsset |
| params | struct ILpStrategy.SwapAndIncreaseLiquidityParams | The parameters for swapping and increasing the liquidity |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _increaseLiquidity

```solidity
function _increaseLiquidity(struct AssetLib.Asset[] assets, struct ILpStrategy.IncreaseLiquidityParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

increases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to increase the liquidity assets[2] = lpAsset |
| params | struct ILpStrategy.IncreaseLiquidityParams | The parameters for increasing the liquidity |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### decreaseLiquidityAndSwap

```solidity
function decreaseLiquidityAndSwap(struct AssetLib.Asset[] assets, struct ILpStrategy.DecreaseLiquidityAndSwapParams params, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Decreases the liquidity of the position and swaps the other token to the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to decrease the liquidity assets[0] = lpAsset |
| params | struct ILpStrategy.DecreaseLiquidityAndSwapParams | The parameters for decreasing the liquidity and swapping |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _decreaseLiquidity

```solidity
function _decreaseLiquidity(struct AssetLib.Asset lpAsset, struct ILpStrategy.DecreaseLiquidityParams params, struct ICommon.FeeConfig feeConfig, address principalToken, bool allowDeposit) internal returns (struct AssetLib.Asset[] returnAssets)
```

Decreases the liquidity of the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| lpAsset | struct AssetLib.Asset | The assets to decrease the liquidity assets[0] = lpAsset |
| params | struct ILpStrategy.DecreaseLiquidityParams | The parameters for decreasing the liquidity |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |
| principalToken | address |  |
| allowDeposit | bool |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### swapAndRebalancePosition

```solidity
function swapAndRebalancePosition(struct AssetLib.Asset[] assets, struct ILpStrategy.SwapAndRebalancePositionParams params, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Swaps the principal token to the other token and rebalances the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to swap and rebalance, assets[0] = principalToken, assets[1] = lpAsset |
| params | struct ILpStrategy.SwapAndRebalancePositionParams | The parameters for swapping and rebalancing the position |
| vaultConfig | struct ICommon.VaultConfig | The vault configuration |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### swapAndCompound

```solidity
function swapAndCompound(struct AssetLib.Asset[] assets, struct ILpStrategy.SwapAndCompoundParams params, struct ICommon.VaultConfig vaultConfig, struct ICommon.FeeConfig feeConfig) internal returns (struct AssetLib.Asset[] returnAssets)
```

Swaps the principal token to the other token and compounds the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | struct AssetLib.Asset[] | The assets to swap and compound, assets[0] = principalToken |
| params | struct ILpStrategy.SwapAndCompoundParams | The parameters for swapping and compounding the position |
| vaultConfig | struct ICommon.VaultConfig |  |
| feeConfig | struct ICommon.FeeConfig | The fee configuration |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| returnAssets | struct AssetLib.Asset[] | The assets that were returned to the msg.sender |

### _optimalSwapFromPrincipal

```solidity
function _optimalSwapFromPrincipal(struct ILpStrategy.SwapFromPrincipalParams params, bool checkPriceSanity) internal returns (uint256 amount0, uint256 amount1)
```

Swaps the principal token to the other token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ILpStrategy.SwapFromPrincipalParams | The parameters for swapping the principal token |
| checkPriceSanity | bool |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The amount of token0 |
| amount1 | uint256 | The amount of token1 |

### _swapToPrincipal

```solidity
function _swapToPrincipal(struct ILpStrategy.SwapToPrincipalParams params, bool checkPriceSanity) internal returns (uint256 amountOut, uint256 amountInUsed)
```

Swaps the token to the principal token

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ILpStrategy.SwapToPrincipalParams | The parameters for swapping the token |
| checkPriceSanity | bool |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | uint256 | The result amount of principal token |
| amountInUsed | uint256 | The amount of token used |

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external view
```

Revalidate the position

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | struct AssetLib.Asset | The asset to revalidate |
| config | struct ICommon.VaultConfig | The vault configuration |

### _getPoolForPosition

```solidity
function _getPoolForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (contract IPancakeV3Pool pool)
```

_Gets the pool for the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| tokenId | uint256 | The token id of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | contract IPancakeV3Pool | The pool for the position |

### _getAmountsForPosition

```solidity
function _getAmountsForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (uint256 amount0, uint256 amount1)
```

_Gets the amounts for the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| tokenId | uint256 | The token id of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The amount of token0 |
| amount1 | uint256 | The amount of token1 |

### _getFeesForPosition

```solidity
function _getFeesForPosition(contract INonfungiblePositionManager nfpm, uint256 tokenId) internal view returns (uint256 fee0, uint256 fee1)
```

_Gets the fees for the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| tokenId | uint256 | The token id of the position |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| fee0 | uint256 | The fee of token0 |
| fee1 | uint256 | The fee of token1 |

### _getFeeGrowthInside

```solidity
function _getFeeGrowthInside(contract IPancakeV3Pool pool, int24 tickLower, int24 tickUpper, int24 tickCurrent) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
```

_Gets the fee growth inside the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | contract IPancakeV3Pool | The pool for the position |
| tickLower | int24 | The lower tick of the position |
| tickUpper | int24 | The upper tick of the position |
| tickCurrent | int24 | The current tick of the pool |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| feeGrowthInside0X128 | uint256 | The fee growth of token0 |
| feeGrowthInside1X128 | uint256 | The fee growth of token1 |

### _takeFees

```solidity
function _takeFees(address token0, uint256 amount0, address token1, uint256 amount1, struct ICommon.FeeConfig feeConfig, address principalToken, address pool, bool validatePriceSanity) internal returns (uint256, uint256)
```

### _safeResetAndApprove

```solidity
function _safeResetAndApprove(contract IERC20 token, address _spender, uint256 _value) internal
```

_some tokens require allowance == 0 to approve new amount
but some tokens does not allow approve amount = 0
we try to set allowance = 0 before approve new amount. if it revert means that
the token not allow to approve 0, which means the following line code will work properly_

### _safeApprove

```solidity
function _safeApprove(contract IERC20 token, address _spender, uint256 _value) internal
```

### _checkAssetStrategy

```solidity
function _checkAssetStrategy(address strategy) internal view
```

_check old lp strategy for backward compatibility
This was implemented as a migration method since old lp strategies have a bug_

### receive

```solidity
receive() external payable
```

Fallback function to receive Ether. This is required for the contract to accept ETH transfers.

