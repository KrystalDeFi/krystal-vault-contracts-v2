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

### setStableTokens

```solidity
function setStableTokens(address[] _stableTokens, bool _isStable) external
```

### isStableToken

```solidity
function isStableToken(address _token) external view returns (bool _isStableToken)
```

### setPeggedTokens

```solidity
function setPeggedTokens(address[] _peggedTokens, bool _isPegged) external
```

### isPeggedToken

```solidity
function isPeggedToken(address _token) external view returns (bool _isPeggedToken)
```

### getStrategyConfig

```solidity
function getStrategyConfig(address _strategy, address _principalToken, uint8 _type) external view returns (bytes)
```

### setStrategyConfig

```solidity
function setStrategyConfig(address _strategy, address _principalToken, uint8 _type, bytes _config) external
```

### setMaxPositions

```solidity
function setMaxPositions(uint8 _maxPositions) external
```

