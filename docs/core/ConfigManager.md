# Solidity API

## ConfigManager

### whitelistStrategies

```solidity
mapping(address => bool) whitelistStrategies
```

### whitelistSwapRouters

```solidity
mapping(address => bool) whitelistSwapRouters
```

### whitelistAutomators

```solidity
mapping(address => bool) whitelistAutomators
```

### strategyConfigs

```solidity
mapping(address => mapping(address => bytes)) strategyConfigs
```

### maxPositions

```solidity
uint8 maxPositions
```

### maxHarvestSlippage

```solidity
int24 maxHarvestSlippage
```

### isVaultPaused

```solidity
bool isVaultPaused
```

### constructor

```solidity
constructor(address _owner, address[] _whitelistAutomator, address[] _typedTokens, uint256[] _typedTokenTypes) public
```

### whitelistStrategy

```solidity
function whitelistStrategy(address[] _strategies, bool _isWhitelisted) external
```

Whitelist strategy

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategies | address[] | Array of strategy addresses |
| _isWhitelisted | bool | Boolean value to whitelist or unwhitelist |

### isWhitelistedStrategy

```solidity
function isWhitelistedStrategy(address _strategy) external view returns (bool)
```

Check if strategy is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategy | address | Strategy address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | _isWhitelisted Boolean value if strategy is whitelisted |

### whitelistSwapRouter

```solidity
function whitelistSwapRouter(address[] _swapRouters, bool _isWhitelisted) external
```

Whitelist swap router

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _swapRouters | address[] | Array of swap router addresses |
| _isWhitelisted | bool | Boolean value to whitelist or unwhitelist |

### isWhitelistedSwapRouter

```solidity
function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool)
```

Check if swap router is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _swapRouter | address | Swap router address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | _isWhitelisted Boolean value if swap router is whitelisted |

### whitelistAutomator

```solidity
function whitelistAutomator(address[] _automators, bool _isWhitelisted) external
```

Whitelist automator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _automators | address[] | Array of automator addresses |
| _isWhitelisted | bool | Boolean value to whitelist or unwhitelist |

### isWhitelistedAutomator

```solidity
function isWhitelistedAutomator(address _automator) external view returns (bool)
```

Check if automator is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _automator | address | Automator address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | _isWhitelisted Boolean value if automator is whitelisted |

### getTypedTokens

```solidity
function getTypedTokens() external view returns (address[] _typedTokens, uint256[] _typedTokenTypes)
```

Get typed tokens

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| _typedTokens | address[] | Typed tokens |
| _typedTokenTypes | uint256[] | Typed token types |

### getTypedToken

```solidity
function getTypedToken(address _token) external view returns (uint256 _type)
```

Get typed token type

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _token | address | Token address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| _type | uint256 | Token type |

### setTypedTokens

```solidity
function setTypedTokens(address[] _typedTokens, uint256[] _typedTokenTypes) external
```

Set typed tokens

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _typedTokens | address[] | Array of typed token addresses |
| _typedTokenTypes | uint256[] | Array of typed token types |

### isMatchedWithType

```solidity
function isMatchedWithType(address _token, uint256 _type) external view returns (bool)
```

Check if token is matched with type

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _token | address | Token address |
| _type | uint256 | Token type |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | _isMatched Boolean value if token is stable |

### getStrategyConfig

```solidity
function getStrategyConfig(address _strategy, address _principalToken) external view returns (bytes)
```

Get strategy config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategy | address | Strategy address |
| _principalToken | address | Principal token address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bytes | _config Strategy config |

### setStrategyConfig

```solidity
function setStrategyConfig(address _strategy, address _principalToken, bytes _config) external
```

Set strategy config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategy | address | Strategy address |
| _principalToken | address | Principal token address |
| _config | bytes | Strategy config |

### setMaxPositions

```solidity
function setMaxPositions(uint8 _maxPositions) external
```

Set max positions

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _maxPositions | uint8 | Max positions |

### setMaxHarvestSlippage

```solidity
function setMaxHarvestSlippage(int24 _maxHarvestSlippage) external
```

Set max harvest slippage

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _maxHarvestSlippage | int24 | Max harvest slippage |

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

Set vault paused

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _isVaultPaused | bool | Boolean value to set vault paused or unpaused |

### setFeeConfig

```solidity
function setFeeConfig(bool allowDeposit, struct ICommon.FeeConfig _feeConfig) external
```

Set fee config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| allowDeposit | bool | Boolean value to set fee config for public or private vault |
| _feeConfig | struct ICommon.FeeConfig | Fee config |

### getFeeConfig

```solidity
function getFeeConfig(bool allowDeposit) external view returns (struct ICommon.FeeConfig)
```

Get fee config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| allowDeposit | bool | Boolean value to get fee config for public or private vault |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct ICommon.FeeConfig | _feeConfig Fee config |

