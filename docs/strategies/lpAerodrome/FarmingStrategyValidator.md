# Solidity API

## FarmingStrategyValidator

Validates ICLGauge addresses against whitelisted factories

_Prevents malicious gauge attacks by ensuring gauges belong to trusted factories_

### whitelistedFactories

```solidity
mapping(address => bool) whitelistedFactories
```

### constructor

```solidity
constructor(address initialOwner, address[] initialFactories) public
```

Constructor

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| initialOwner | address | Address of the initial owner |
| initialFactories | address[] | Array of initial factory addresses to whitelist |

### validateGauge

```solidity
function validateGauge(address gauge) external view
```

Validate that a gauge address is safe to use

_Reverts if gauge is invalid or belongs to non-whitelisted factory_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| gauge | address | Address of the ICLGauge to validate |

### isValidGauge

```solidity
function isValidGauge(address gauge) external view returns (bool valid)
```

Check if a gauge address is valid without reverting

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| gauge | address | Address of the ICLGauge to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True if gauge is valid, false otherwise |

### isWhitelistedFactory

```solidity
function isWhitelistedFactory(address factory) external view returns (bool whitelisted)
```

Check if a factory is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| factory | address | Address of the ICLFactory to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| whitelisted | bool | True if factory is whitelisted, false otherwise |

### addFactory

```solidity
function addFactory(address factory) external
```

Add a factory to the whitelist

_Only callable by owner_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| factory | address | Address of the ICLFactory to whitelist |

### removeFactory

```solidity
function removeFactory(address factory) external
```

Remove a factory from the whitelist

_Only callable by owner_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| factory | address | Address of the ICLFactory to remove |

### getWhitelistedFactories

```solidity
function getWhitelistedFactories() external view returns (address[] factories)
```

Get all whitelisted factories

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| factories | address[] | Array of whitelisted factory addresses |

### _addFactory

```solidity
function _addFactory(address factory) internal
```

Internal function to add a factory to the whitelist

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| factory | address | Address of the ICLFactory to whitelist |

