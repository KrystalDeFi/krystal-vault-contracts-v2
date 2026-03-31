# Solidity API

## ISharedVault

### VaultDeposit

```solidity
event VaultDeposit(address vaultFactory, address account, uint256[4] amounts, uint256 shares)
```

### VaultWithdraw

```solidity
event VaultWithdraw(address vaultFactory, address account, uint256[4] amounts, uint256 shares)
```

### VaultExecute

```solidity
event VaultExecute(address vaultFactory, address strategy, bytes data)
```

### VaultSwap

```solidity
event VaultSwap(address vaultFactory, address swapTarget, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
```

### SetVaultAdmin

```solidity
event SetVaultAdmin(address vaultFactory, address account, bool isAdmin)
```

### SetVaultOperator

```solidity
event SetVaultOperator(address vaultFactory, address previousOperator, address newOperator)
```

### VaultOwnerChanged

```solidity
event VaultOwnerChanged(address vaultFactory, address previousOwner, address newOwner)
```

### VaultPausedUpdated

```solidity
event VaultPausedUpdated(address vaultFactory, bool paused)
```

### Position

_Tracked LP position_

```solidity
struct Position {
  address strategy;
  address nfpm;
  uint256 tokenId;
  address token0;
  address token1;
}
```

### initialize

```solidity
function initialize(string name, address[4] _tokens, uint256[4] initialAmounts, address _owner, address _configManager, address _weth) external
```

### deposit

```solidity
function deposit(uint256[4] amounts, uint256 minShares) external payable returns (uint256 shares)
```

Deposit tokens and receive shares. Send ETH via msg.value to auto-wrap to WETH
        (msg.value must match amounts[wethIndex] exactly).

### withdraw

```solidity
function withdraw(uint256 shares, uint256[4] minAmounts, bool unwrap) external returns (uint256[4] amounts)
```

Burn shares and withdraw proportional idle tokens.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 |  |
| minAmounts | uint256[4] |  |
| unwrap | bool | If true, any WETH amount is unwrapped to native ETH before sending. |

### execute

```solidity
function execute(address strategy, bytes data) external payable
```

### swap

```solidity
function swap(address swapTarget, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes swapData) external
```

### getTokens

```solidity
function getTokens() external view returns (address[4])
```

### getIdleBalances

```solidity
function getIdleBalances() external view returns (uint256[4])
```

### getTotalBalances

```solidity
function getTotalBalances() external view returns (uint256[4])
```

### getPositionCount

```solidity
function getPositionCount() external view returns (uint256)
```

### getPosition

```solidity
function getPosition(uint256 index) external view returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1)
```

### previewDeposit

```solidity
function previewDeposit(uint256[4] amounts) external view returns (uint256 shares)
```

### previewWithdraw

```solidity
function previewWithdraw(uint256 shares) external view returns (uint256[4] amounts)
```

### isVaultToken

```solidity
function isVaultToken(address token) external view returns (bool)
```

### vaultOwner

```solidity
function vaultOwner() external view returns (address)
```

### weth

```solidity
function weth() external view returns (address)
```

### tokenCount

```solidity
function tokenCount() external view returns (uint16)
```

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

### setOperator

```solidity
function setOperator(address _operator) external
```

### setPaused

```solidity
function setPaused(bool _paused) external
```

### transferOwnership

```solidity
function transferOwnership(address newOwner) external
```

### sweepTokens

```solidity
function sweepTokens(address[] _tokens, uint256[] amounts, address to) external
```

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount, address to) external
```

### sweepERC721

```solidity
function sweepERC721(address token, uint256 tokenId, address to) external
```

### sweepERC1155

```solidity
function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external
```

