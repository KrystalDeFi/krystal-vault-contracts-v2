# Solidity API

## IMerklAutomator

### InvalidAssetStrategy

```solidity
error InvalidAssetStrategy()
```

### executeAllocate

```solidity
function executeAllocate(contract IVault vault, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint64 gasFeeX64, bytes allocateCalldata, bytes abiEncodedUserOrder, bytes orderSignature) external
```

