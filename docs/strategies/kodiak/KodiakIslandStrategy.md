# Solidity API

## KodiakIslandStrategy

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

### optimalSwapper

```solidity
contract IOptimalSwapper optimalSwapper
```

### lpFeeTaker

```solidity
contract ILpFeeTaker lpFeeTaker
```

### whitelistRewardVaultFactory

```solidity
address whitelistRewardVaultFactory
```

### bgtToken

```solidity
contract IBGT bgtToken
```

### wbera

```solidity
address wbera
```

### KodiakIslandStrategyCompound

```solidity
event KodiakIslandStrategyCompound(address vaultAddress, uint256 amount0Collected, uint256 amount1Collected, struct AssetLib.Asset[] compoundAssets)
```

### constructor

```solidity
constructor(address _optimalSwapper, address _whitelistRewardVaultFactory, address _lpFeeTaker, address _bgtToken, address _wbera) public
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset asset, address principalToken) external view returns (uint256 valueInPrincipal)
```

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes data) external payable returns (struct AssetLib.Asset[])
```

### _swapAndStake

```solidity
function _swapAndStake(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig, bytes params) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _withdrawAndSwap

```solidity
function _withdrawAndSwap(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig, bytes params) internal returns (struct AssetLib.Asset[])
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

### _takeFee

```solidity
function _takeFee(address token, uint256 amount, struct ICommon.FeeConfig feeConfig) internal returns (uint256 totalFeeAmount)
```

### harvest

```solidity
function harvest(struct AssetLib.Asset asset, address, uint256, struct ICommon.VaultConfig, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset existingAsset, uint256 principalTokenAmount, struct ICommon.VaultConfig config) external payable returns (struct AssetLib.Asset[])
```

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset existingAsset, uint256 shares, uint256 totalSupply, struct ICommon.VaultConfig config, struct ICommon.FeeConfig feeConfig) external payable returns (struct AssetLib.Asset[] returnAssets)
```

### revalidate

```solidity
function revalidate(struct AssetLib.Asset asset, struct ICommon.VaultConfig config) external
```

### _harvestAndTakeFee

```solidity
function _harvestAndTakeFee(contract IRewardVault rewardVault, struct ICommon.FeeConfig feeConfig) internal returns (uint256 redeemedBera)
```

### receive

```solidity
receive() external payable
```

