# Solidity API

## MerklAutomator

Contract that allows anyone to trigger Merkl reward claims through vault allocation

### configManager

```solidity
contract IConfigManager configManager
```

### constructor

```solidity
constructor(address _owner, address _configManager) public
```

### executeAllocate

```solidity
function executeAllocate(contract IVault vault, struct AssetLib.Asset[] inputAssets, contract IStrategy strategy, uint64 gasFeeX64, bytes allocateData, bytes, bytes) external
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
|  | bytes |  |
|  | bytes |  |

### pause

```solidity
function pause() external
```

Pause the contract

### unpause

```solidity
function unpause() external
```

Unpause the contract

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view
```

Check if the caller has permission to withdraw

_Must be implemented by the child contract_

