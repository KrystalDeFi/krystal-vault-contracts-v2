# Solidity API

## VaultFactory

### WETH

```solidity
address WETH
```

### configManager

```solidity
address configManager
```

### vaultImplementation

```solidity
address vaultImplementation
```

### platformFeeRecipient

```solidity
address platformFeeRecipient
```

### platformFeeBasisPoint

```solidity
uint16 platformFeeBasisPoint
```

### vaultsByAddress

```solidity
mapping(address => address[]) vaultsByAddress
```

### allVaults

```solidity
address[] allVaults
```

### constructor

```solidity
constructor(address _owner, address _weth, address _configManager, address _vaultImplementation, address _platformFeeRecipient, uint16 _platformFeeBasisPoint) public
```

### createVault

```solidity
function createVault(struct ICommon.VaultCreateParams params) external payable returns (address vault)
```

Create a new vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| params | struct ICommon.VaultCreateParams | Vault creation parameters |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | address | Address of the new vault |

### pause

```solidity
function pause() public
```

Pause the contract

### unpause

```solidity
function unpause() public
```

Unpause the contract

### setConfigManager

```solidity
function setConfigManager(address _configManager) public
```

Set the ConfigManager address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _configManager | address | Address of the new ConfigManager |

### setVaultImplementation

```solidity
function setVaultImplementation(address _vaultImplementation) public
```

Set the Vault implementation

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vaultImplementation | address | Address of the new vault implementation |

### setPlatformFeeRecipient

```solidity
function setPlatformFeeRecipient(address _platformFeeRecipient) public
```

Set the default platform fee recipient

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _platformFeeRecipient | address | Address of the new platform fee recipient |

### setPlatformFeeBasisPoint

```solidity
function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) public
```

Set the default platform fee basis point

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _platformFeeBasisPoint | uint16 | New platform fee basis point |

