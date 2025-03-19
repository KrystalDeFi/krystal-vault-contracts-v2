# Solidity API

## IConfigManager

### maxPositions

```solidity
function maxPositions() external view returns (uint8)
```

### whitelistStrategy

```solidity
function whitelistStrategy(address[] _strategies, bool _isWhitelisted) external
```

### isWhitelistedStrategy

```solidity
function isWhitelistedStrategy(address _strategy) external view returns (bool _isWhitelisted)
```

### whitelistSwapRouter

```solidity
function whitelistSwapRouter(address[] _swapRouters, bool _isWhitelisted) external
```

### isWhitelistedSwapRouter

```solidity
function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool _isWhitelisted)
```

### whitelistAutomator

```solidity
function whitelistAutomator(address[] _automators, bool _isWhitelisted) external
```

### isWhitelistedAutomator

```solidity
function isWhitelistedAutomator(address _automator) external view returns (bool _isWhitelisted)
```

### getTypedTokens

```solidity
function getTypedTokens() external view returns (address[] _typedTokens, uint256[] _typedTokenTypes)
```

### setTypedTokens

```solidity
function setTypedTokens(address[] _typedTokens, uint256[] _typedTokenTypes) external
```

### isMatchedWithType

```solidity
function isMatchedWithType(address _token, uint256 _type) external view returns (bool)
```

### getStrategyConfig

```solidity
function getStrategyConfig(address _strategy, address _principalToken) external view returns (bytes)
```

### setStrategyConfig

```solidity
function setStrategyConfig(address _strategy, address _principalToken, bytes _config) external
```

### setMaxPositions

```solidity
function setMaxPositions(uint8 _maxPositions) external
```

