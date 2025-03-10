# Solidity API

## VaultFactory

### WETH

```solidity
address WETH
```

### whitelistManager

```solidity
address whitelistManager
```

### vaultImplementation

```solidity
address vaultImplementation
```

### vaultAutomator

```solidity
address vaultAutomator
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
constructor(address _weth, address _whiteListManager, address _vaultImplementation, address _vaultAutomator, address _platformFeeRecipient, uint16 _platformFeeBasisPoint) public
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

### setWhitelistManager

```solidity
function setWhitelistManager(address _whitelistManager) public
```

Set the WhitelistManager address

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _whitelistManager | address | Address of the new WhitelistManager |

### setVaultImplementation

```solidity
function setVaultImplementation(address _vaultImplementation) public
```

Set the Vault implementation

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vaultImplementation | address | Address of the new vault implementation |

### setVaultAutomator

```solidity
function setVaultAutomator(address _vaultAutomator) public
```

Set the VaultAutomator address

### setPlatformFeeRecipient

```solidity
function setPlatformFeeRecipient(address _platformFeeRecipient) public
```

Set the default platform fee recipient

### setPlatformFeeBasisPoint

```solidity
function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) public
```

Set the default platform fee basis point

