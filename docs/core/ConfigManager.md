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
mapping(address => mapping(address => mapping(uint8 => bytes))) strategyConfigs
```

### stableTokens

```solidity
address[] stableTokens
```

### maxPositions

```solidity
uint8 maxPositions
```

### constructor

```solidity
constructor(address _owner, address[] _stableTokens, address[] _whitelistAutomator) public
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
function isWhitelistedStrategy(address _strategy) external view returns (bool _isWhitelisted)
```

Check if strategy is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategy | address | Strategy address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| _isWhitelisted | bool | Boolean value if strategy is whitelisted |

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
function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool _isWhitelisted)
```

Check if swap router is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _swapRouter | address | Swap router address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| _isWhitelisted | bool | Boolean value if swap router is whitelisted |

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
function isWhitelistedAutomator(address _automator) external view returns (bool _isWhitelisted)
```

Check if automator is whitelisted

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _automator | address | Automator address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| _isWhitelisted | bool | Boolean value if automator is whitelisted |

### setStableTokens

```solidity
function setStableTokens(address[] _stableTokens) external
```

Set stable tokens

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _stableTokens | address[] | Array of stable token addresses |

### isStableToken

```solidity
function isStableToken(address _token) external view returns (bool _isStable)
```

Check if token is stable

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _token | address | Token address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| _isStable | bool | Boolean value if token is stable |

### getStrategyConfig

```solidity
function getStrategyConfig(address _strategy, address _principalToken, uint8 _type) external view returns (bytes)
```

Get strategy config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategy | address | Strategy address |
| _principalToken | address |  |
| _type | uint8 | Strategy type |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bytes | _config Strategy config |

### setStrategyConfig

```solidity
function setStrategyConfig(address _strategy, address _principalToken, uint8 _type, bytes _config) external
```

Set strategy config

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _strategy | address | Strategy address |
| _principalToken | address |  |
| _type | uint8 | Strategy type |
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

