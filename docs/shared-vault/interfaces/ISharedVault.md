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

### PositionDropped

```solidity
event PositionDropped(address vaultFactory, address nfpm, uint256 tokenId)
```

Emitted when the vault owner forcibly drops a position from tracking.
        The underlying LP liquidity is NOT exited — the NFT remains in the vault
        but is no longer valued or interacted with. Used to unblock deposits when
        a position's strategy is broken or the pool is permanently rugged.

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
function deposit(uint256[4] amounts, uint16 slippageBps, uint256 minShares) external payable returns (uint256 shares)
```

Deposit tokens and receive shares. Send ETH via msg.value to auto-wrap to WETH
        (msg.value must match amounts[wethIndex] exactly; only the proportional amount
         is wrapped — excess ETH is refunded directly without an unwrap round-trip).

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amounts | uint256[4] |  |
| slippageBps | uint16 | Slippage tolerance in basis points (e.g. 100 = 1%) applied to each LP        position's proportional deposit: amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000).        Must be ≤ 10000. Pass 0 to skip the amountMin floor. |
| minShares | uint256 | Minimum vault shares the caller is willing to receive. Computed off-chain from        `previewDeposit(amounts)` minus acceptable share-price slippage; pass 0 to skip.        Guards against vault-balance manipulation between tx submission and on-chain inclusion. |

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

### dropPosition

```solidity
function dropPosition(address nfpm, uint256 tokenId) external
```

Forcibly remove a position from vault tracking without exiting liquidity.
        The NFT remains in the vault but is no longer valued in `getTotalBalances()`,
        iterated during `withdraw()`, or deposited into during `deposit()`.
        Use when a position's pool is permanently rugged or the strategy is irreparably
        broken and `strategyUpdates` cannot fix it (e.g. the NFPM itself is bricked).
        After dropping, any tokens still locked in the position are effectively lost —
        use `sweepERC721` to recover the NFT if it's still transferable.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT position manager that issued the position |
| tokenId | uint256 | The position token ID to drop |

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
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

