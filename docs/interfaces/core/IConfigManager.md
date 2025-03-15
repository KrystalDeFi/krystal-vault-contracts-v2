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

### setStableTokens

```solidity
function setStableTokens(address[] _stableTokens) external
```

### isStableToken

```solidity
function isStableToken(address _token) external view returns (bool _isStableToken)
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

