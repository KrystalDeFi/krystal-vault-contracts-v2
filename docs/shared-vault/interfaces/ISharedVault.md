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
event VaultExecute(address vaultFactory, address target, bytes data)
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

### VaultOwnerFeeBasisPointUpdated

```solidity
event VaultOwnerFeeBasisPointUpdated(address vaultFactory, uint16 basisPoints)
```

### PositionStrategyMigrated

```solidity
event PositionStrategyMigrated(address vaultFactory, address nfpm, uint256 tokenId, address oldStrategy, address newStrategy)
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

### Action

_A single unit of work passed to execute(). See ISharedCommon.CallType for full semantics._

```solidity
struct Action {
  address target;
  bytes data;
  enum ISharedCommon.CallType callType;
}
```

### PositionStrategyUpdate

_Explicit strategy pointer update bundled with execute().
     Allows migrating a position to a new whitelisted strategy in the same transaction as the
     first action executed via that strategy, without a separate owner-only call._

```solidity
struct PositionStrategyUpdate {
  address nfpm;
  uint256 tokenId;
  address strategy;
}
```

### initialize

```solidity
function initialize(string name, address[4] _tokens, uint256[4] initialAmounts, address _owner, address _operator, address _configManager, address _weth) external
```

### deposit

```solidity
function deposit(uint256[4] amounts, uint256 minShares) external payable returns (uint256 shares)
```

Deposit tokens and receive shares. Send ETH via msg.value to auto-wrap to WETH
        (msg.value must match amounts[wethIndex] exactly; only the proportional amount
         is wrapped — excess ETH is refunded directly without an unwrap round-trip).

### withdraw

```solidity
function withdraw(uint256 shares, uint256[4] minAmounts, bool unwrap) external returns (uint256[4] amounts)
```

Burn shares and withdraw proportional tokens.
        If the vault has active LP positions, each strategy exits its proportional share
        of liquidity first; idle tokens are then withdrawn.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | Number of vault shares to burn. |
| minAmounts | uint256[4] | Per-token minimum output (aggregate slippage guard).        Individual LP exits use zero slippage bounds so one tight position cannot        revert the whole withdrawal. Instead, any sandwich-induced shortfall reduces        the aggregate `amounts[i]` and is caught here. Derive values from        `previewWithdraw()` minus acceptable slippage. |
| unwrap | bool | If true, any WETH amount is unwrapped to native ETH before sending. |

### execute

```solidity
function execute(struct ISharedVault.Action[] actions, struct ISharedVault.PositionStrategyUpdate[] strategyUpdates) external
```

Execute one or more actions: strategy delegatecalls (LP) and/or direct swap calls.
        For strategy actions the vault tracks LP position changes.
        For swap actions the vault validates tokenIn/tokenOut are vault tokens and checks
        that the output meets minAmountOut.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| actions | struct ISharedVault.Action[] |  |
| strategyUpdates | struct ISharedVault.PositionStrategyUpdate[] | Optional list of position→strategy pointer updates applied before        actions run. Use to migrate a broken strategy in the same tx as the first action        via its replacement. Each strategy must be whitelisted in configManager. |

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

### configManager

```solidity
function configManager() external view returns (contract ISharedConfigManager)
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

### vaultOwnerFeeBasisPoint

```solidity
function vaultOwnerFeeBasisPoint() external view returns (uint16)
```

Basis points of LP performance/collection fees routed to `vaultOwner` on proportional exits (max 10_000).

### setVaultOwnerFeeBasisPoint

```solidity
function setVaultOwnerFeeBasisPoint(uint16 basisPoints) external
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

