# Solidity API

## MerklAutomator

Contract that allows anyone to trigger Merkl reward claims through vault allocation

### configManager

```solidity
contract IConfigManager configManager
```

### initialize

```solidity
function initialize(address _configManager) public
```

Initializes the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _configManager | address | Address of the config manager |

### executeAllocate

```solidity
function executeAllocate(contract IVault vault, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint64 gasFeeX64, bytes allocateData, bytes abiEncodedUserOrder, bytes orderSignature) external
```

Execute an allocate on a Vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | contract IVault | Vault |
| inputAssets | struct AssetLib.Asset[] | Input assets |
| strategy | contract IStrategy | Strategy |
| gasFeeX64 | uint64 |  |
| allocateData | bytes | allocateData data to be passed to vault's allocate function |
| abiEncodedUserOrder | bytes | ABI encoded user order |
| orderSignature | bytes | Signature of the order |

