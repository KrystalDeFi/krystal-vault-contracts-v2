# Solidity API

## LpStrategy

### Instruction

```solidity
struct Instruction {
  address abc;
}
```

### principalToken

```solidity
address principalToken
```

### constructor

```solidity
constructor(address _principalToken) public
```

### valueOf

```solidity
function valueOf(struct ICommon.Asset asset) external view returns (uint256 value)
```

Deposits the asset to the strategy

### convert

```solidity
function convert(struct ICommon.Asset[] assets, bytes data) external returns (struct ICommon.Asset[])
```

Converts the asset to another assets

### convertIntoExisting

```solidity
function convertIntoExisting(struct ICommon.Asset existingAsset, struct ICommon.Asset[] newAssets, bytes data) external returns (struct ICommon.Asset[] asset)
```

