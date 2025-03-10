# Solidity API

## WhitelistManager

### whitelistStrategies

```solidity
mapping(address => bool) whitelistStrategies
```

### constructor

```solidity
constructor() public
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

### isWhitelisted

```solidity
function isWhitelisted(address _strategy) external view returns (bool _isWhitelisted)
```

