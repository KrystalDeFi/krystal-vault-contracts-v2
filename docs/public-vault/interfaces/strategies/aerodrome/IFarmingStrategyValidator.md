# Solidity API

## IFarmingStrategyValidator

Interface for validating ICLGauge addresses in FarmingStrategy

_Validates that gauges belong to whitelisted factories to prevent malicious gauge attacks_

### FactoryAdded

```solidity
event FactoryAdded(address factory)
```

### FactoryRemoved

```solidity
event FactoryRemoved(address factory)
```

### ZeroAddress

```solidity
error ZeroAddress()
```

### InvalidFactory

```solidity
error InvalidFactory()
```

### InvalidGauge

```solidity
error InvalidGauge()
```

### FactoryAlreadyAdded

```solidity
error FactoryAlreadyAdded()
```

### FactoryNotFound

```solidity
error FactoryNotFound()
```

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

_Only callable by authorized admin_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| factory | address | Address of the ICLFactory to whitelist |

### removeFactory

```solidity
function removeFactory(address factory) external
```

Remove a factory from the whitelist

_Only callable by authorized admin_

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

