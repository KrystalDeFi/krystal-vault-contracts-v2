# Solidity API

## LpValidator

### configManager

```solidity
contract IConfigManager configManager
```

### constructor

```solidity
constructor(address _configManager) public
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
function validateTickWidth(contract INonfungiblePositionManager nfpm, uint24 fee, address token0, address token1, int24 tickLower, int24 tickUpper, struct ICommon.VaultConfig config) external view
```

_Checks the tick width of the position_

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

### _getAmountsForPool

```solidity
function _getAmountsForPool(contract IUniswapV3Pool pool) internal view returns (uint256 amount0, uint256 amount1)
```

_Gets the amounts for the pool_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pool | contract IUniswapV3Pool | IUniswapV3Pool |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount0 | uint256 | The amount of token0 |
| amount1 | uint256 | The amount of token1 |

