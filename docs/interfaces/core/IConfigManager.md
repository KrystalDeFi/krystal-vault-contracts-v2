# Solidity API

## IConfigManager

### MaxPositionsSet

```solidity
event MaxPositionsSet(uint8 _maxPositions)
```

### MaxHarvestSlippageSet

```solidity
event MaxHarvestSlippageSet(int24 _maxHarvestSlippage)
```

### VaultPausedSet

```solidity
event VaultPausedSet(bool _isVaultPaused)
```

### WhitelistStrategy

```solidity
event WhitelistStrategy(address[] _strategies, bool _isWhitelisted)
```

### WhitelistSwapRouter

```solidity
event WhitelistSwapRouter(address[] _swapRouters, bool _isWhitelisted)
```

### WhitelistAutomator

```solidity
event WhitelistAutomator(address[] _automators, bool _isWhitelisted)
```

### WhitelistSigner

```solidity
event WhitelistSigner(address[] _signers, bool _isWhitelisted)
```

### SetStrategyConfig

```solidity
event SetStrategyConfig(address _strategy, address _principalToken, bytes _config)
```

### SetTypedTokens

```solidity
event SetTypedTokens(address[] _typedTokens, uint256[] _typedTokenTypes)
```

### SetFeeConfig

```solidity
event SetFeeConfig(bool allowDeposit, struct ICommon.FeeConfig _feeConfig)
```

### maxPositions

```solidity
function maxPositions() external view returns (uint8 _maxPositions)
```

### maxHarvestSlippage

```solidity
function maxHarvestSlippage() external view returns (int24 _maxHarvestSlippage)
```

### isVaultPaused

```solidity
function isVaultPaused() external view returns (bool _isVaultPaused)
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

### whitelistSigner

```solidity
function whitelistSigner(address[] signers, bool _isWhitelisted) external
```

### isWhitelistSigner

```solidity
function isWhitelistSigner(address signer) external view returns (bool _isWhitelisted)
```

### getTypedTokens

```solidity
function getTypedTokens() external view returns (address[] _typedTokens, uint256[] _typedTokenTypes)
```

### getTypedToken

```solidity
function getTypedToken(address _token) external view returns (uint256 _type)
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

### setMaxHarvestSlippage

```solidity
function setMaxHarvestSlippage(int24 _maxHarvestSlippage) external
```

### setVaultPaused

```solidity
function setVaultPaused(bool _isVaultPaused) external
```

### setFeeConfig

```solidity
function setFeeConfig(bool allowDeposit, struct ICommon.FeeConfig _feeConfig) external
```

### getFeeConfig

```solidity
function getFeeConfig(bool allowDeposit) external view returns (struct ICommon.FeeConfig)
```

