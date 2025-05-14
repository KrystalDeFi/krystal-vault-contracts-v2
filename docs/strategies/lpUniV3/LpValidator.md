# Solidity API

## LpValidator

### configManager

```solidity
contract IConfigManager configManager
```

### whitelistNfpms

```solidity
mapping(address => bool) whitelistNfpms
```

### constructor

```solidity
constructor(address _configManager, address[] _whitelistNfpms) public
```

### validateNfpm

```solidity
function validateNfpm(address nfpm) external view
```

### validateConfig

```solidity
function validateConfig(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

_Checks the principal amount in the pool_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | contract INonfungiblePositionManager | The non-fungible position manager |
| fee | uint24 | The fee of the pool |
| token0 | address | The token0 of the pool |
| token1 | address | The token1 of the pool |
| tickLower | int24 | The lower tick of the position |
| tickUpper | int24 | The upper tick of the position |
| config | struct ICommon.VaultConfig | The configuration of the strategy |

### validateTickWidth

```solidity
function validateTickWidth(address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

_Checks the tick width of the position_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token0 | address | The token0 of the pool |
| token1 | address | The token1 of the pool |
| tickLower | int24 | The lower tick of the position |
| tickUpper | int24 | The upper tick of the position |
| config | struct ICommon.VaultConfig | The configuration of the strategy |

### validateObservationCardinality

```solidity
function validateObservationCardinality(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1) external view
```

### validatePriceSanity

```solidity
function validatePriceSanity(address pool) external view
```

_Check average price of the last 2 observed ticks compares to current tick_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | address | The pool to check the price |

### _isPoolAllowed

```solidity
function _isPoolAllowed(struct ICommon.VaultConfig config, address pool) internal pure returns (bool)
```

_Checks if the pool is allowed_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| config | struct ICommon.VaultConfig | The configuration of the strategy |
| pool | address | The pool to check |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | allowed If the pool is allowed |

### setWhitelistNfpms

```solidity
function setWhitelistNfpms(address[] _whitelistNfpms, bool isWhitelist) external
```

