# Solidity API

## IOperatorVault

### operator

```solidity
function operator() external view returns (address)
```

## DropPositionStrategy

Emergency public-vault strategy for removing an NFT position from vault accounting.

_Intended to be called through Vault.allocate via delegatecall._

### InstructionType

```solidity
enum InstructionType {
  DropPosition,
  RecoverPosition
}
```

### RecoverPositionParams

```solidity
struct RecoverPositionParams {
  address nfpm;
  uint256 tokenId;
  address strategy;
}
```

### PositionDropped

```solidity
event PositionDropped(address vault, address operator, address nfpm, uint256 tokenId)
```

### PositionRecovered

```solidity
event PositionRecovered(address vault, address operator, address nfpm, uint256 tokenId)
```

### Unauthorized

```solidity
error Unauthorized()
```

### configManager

```solidity
contract IConfigManager configManager
```

### constructor

```solidity
constructor(address _configManager) public
```

### valueOf

```solidity
function valueOf(struct AssetLib.Asset, address) external pure returns (uint256)
```

### convert

```solidity
function convert(struct AssetLib.Asset[] assets, struct ICommon.VaultConfig, struct ICommon.FeeConfig, bytes data) external payable returns (struct AssetLib.Asset[] returnAssets)
```

### harvest

```solidity
function harvest(struct AssetLib.Asset, address, uint256, struct ICommon.VaultConfig, struct ICommon.FeeConfig) external payable returns (struct AssetLib.Asset[])
```

### convertFromPrincipal

```solidity
function convertFromPrincipal(struct AssetLib.Asset, uint256, struct ICommon.VaultConfig) external payable returns (struct AssetLib.Asset[])
```

### convertToPrincipal

```solidity
function convertToPrincipal(struct AssetLib.Asset, uint256, uint256, struct ICommon.VaultConfig, struct ICommon.FeeConfig) external payable returns (struct AssetLib.Asset[])
```

### revalidate

```solidity
function revalidate(struct AssetLib.Asset, struct ICommon.VaultConfig) external pure
```

### _dropPosition

```solidity
function _dropPosition(struct AssetLib.Asset[] assets) internal returns (struct AssetLib.Asset[] returnAssets)
```

### _recoverPosition

```solidity
function _recoverPosition(struct AssetLib.Asset[] assets, struct DropPositionStrategy.RecoverPositionParams params) internal returns (struct AssetLib.Asset[] returnAssets)
```

