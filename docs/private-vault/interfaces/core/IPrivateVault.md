# Solidity API

## IPrivateVault

### InvalidMulticallParams

```solidity
error InvalidMulticallParams()
```

### InvalidTarget

```solidity
error InvalidTarget(address strategy)
```

### StrategyDelegateCallFailed

```solidity
error StrategyDelegateCallFailed()
```

### Paused

```solidity
error Paused()
```

### VaultMulticall

```solidity
event VaultMulticall(address vaultFactory, address[] targets, bytes[] data, enum IPrivateCommon.CallType[] callTypes)
```

### VaultSweepNativeToken

```solidity
event VaultSweepNativeToken(address caller, uint256 amount)
```

### VaultSweepToken

```solidity
event VaultSweepToken(address caller, address[] tokens, uint256[] amounts)
```

### VaultSweepERC721

```solidity
event VaultSweepERC721(address caller, address[] tokens, uint256[] tokenIds)
```

### VaultSweepERC1155

```solidity
event VaultSweepERC1155(address caller, address[] tokens, uint256[] tokenIds, uint256[] amounts)
```

### VaultDepositErc20Tokens

```solidity
event VaultDepositErc20Tokens(address caller, address[] tokens, uint256[] amounts)
```

### VaultDepositErc721Tokens

```solidity
event VaultDepositErc721Tokens(address caller, address[] tokens, uint256[] tokenIds)
```

### VaultDepositErc1155Tokens

```solidity
event VaultDepositErc1155Tokens(address caller, address[] tokens, uint256[] tokenIds, uint256[] amounts)
```

### SetVaultAdmin

```solidity
event SetVaultAdmin(address vaultFactory, address _address, bool _isAdmin)
```

### vaultOwner

```solidity
function vaultOwner() external view returns (address)
```

### initialize

```solidity
function initialize(address _owner, address _configManager) external
```

### multicall

```solidity
function multicall(address[] targets, bytes[] data, enum IPrivateCommon.CallType[] callTypes) external payable
```

### depositErc20Tokens

```solidity
function depositErc20Tokens(address[] tokens, uint256[] amounts) external
```

### depositErc721Tokens

```solidity
function depositErc721Tokens(address[] tokens, uint256[] tokenIds) external
```

### depositErc1155Tokens

```solidity
function depositErc1155Tokens(address[] tokens, uint256[] tokenIds, uint256[] amounts) external
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

