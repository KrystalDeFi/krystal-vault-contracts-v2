# Solidity API

## IPrivateVault

### SetVaultAdmin

```solidity
event SetVaultAdmin(address vaultFactory, address _address, bool _isAdmin)
```

### InvalidMulticallParams

```solidity
error InvalidMulticallParams()
```

### InvalidStrategy

```solidity
error InvalidStrategy(address strategy)
```

### StrategyDelegateCallFailed

```solidity
error StrategyDelegateCallFailed()
```

### Paused

```solidity
error Paused()
```

### initialize

```solidity
function initialize(address _owner, address _configManager) external
```

### multicall

```solidity
function multicall(address[] targets, bytes[] data, enum IPrivateCommon.CallType[] callTypes) external payable
```

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount) external
```

### sweepToken

```solidity
function sweepToken(address[] tokens, uint256[] amounts) external
```

### sweepERC721

```solidity
function sweepERC721(address[] _tokens, uint256[] _tokenIds) external
```

### sweepERC1155

```solidity
function sweepERC1155(address[] _tokens, uint256[] _tokenIds, uint256[] _amounts) external
```

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

