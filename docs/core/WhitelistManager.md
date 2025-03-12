# Solidity API

## WhitelistManager

### whitelistStrategies

```solidity
mapping(address => bool) whitelistStrategies
```

### whitelistSwapRouters

```solidity
mapping(address => bool) whitelistSwapRouters
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

| Name            | Type      | Description                               |
| --------------- | --------- | ----------------------------------------- |
| \_strategies    | address[] | Array of strategy addresses               |
| \_isWhitelisted | bool      | Boolean value to whitelist or unwhitelist |

### isWhitelistedStrategy

```solidity
function isWhitelistedStrategy(address _strategy) external view returns (bool _isWhitelisted)
```

Check if strategy is whitelisted

#### Parameters

| Name       | Type    | Description      |
| ---------- | ------- | ---------------- |
| \_strategy | address | Strategy address |

#### Return Values

| Name            | Type | Description                              |
| --------------- | ---- | ---------------------------------------- |
| \_isWhitelisted | bool | Boolean value if strategy is whitelisted |

### whitelistSwapRouter

```solidity
function whitelistSwapRouter(address[] _swapRouters, bool _isWhitelisted) external
```

Whitelist swap router

#### Parameters

| Name            | Type      | Description                               |
| --------------- | --------- | ----------------------------------------- |
| \_swapRouters   | address[] | Array of swap router addresses            |
| \_isWhitelisted | bool      | Boolean value to whitelist or unwhitelist |

### isWhitelistedSwapRouter

```solidity
function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool _isWhitelisted)
```

Check if swap router is whitelisted

#### Parameters

| Name         | Type    | Description         |
| ------------ | ------- | ------------------- |
| \_swapRouter | address | Swap router address |

#### Return Values

| Name            | Type | Description                                 |
| --------------- | ---- | ------------------------------------------- |
| \_isWhitelisted | bool | Boolean value if swap router is whitelisted |
