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

### VaultOwnerFeeBasisPointSet

```solidity
event VaultOwnerFeeBasisPointSet(address vaultFactory, uint16 basisPoints)
```

Emitted exactly once at vault initialization.

_`vaultOwnerFeeBasisPoint` is locked at initialization and cannot be changed afterward._

### PositionDropped

```solidity
event PositionDropped(address vaultFactory, address nfpm, uint256 tokenId)
```

Emitted when the vault owner forcibly drops a position from tracking.
        The NFT is transferred to the operator (if set) so liquidity can be recovered later;
        if no operator is set the NFT remains in the vault.

### PositionRecovered

```solidity
event PositionRecovered(address vaultFactory, address nfpm, uint256 tokenId)
```

Emitted when the operator recovers a previously dropped position back into tracking.

### Position

_Tracked LP position
     Vault token slots are ERC20 addresses; `address(0)` means an unused slot. Native-currency
     V4/Pancake pools that use `address(0)` as a currency are unsupported. Use wrapped-native
     ERC20 pools instead._

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

### initialize

```solidity
function initialize(string name, address[4] _tokens, uint256[4] initialAmounts, address _owner, address _operator, address _configManager, address _weth, uint16 _vaultOwnerFeeBasisPoint) external
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| name | string |  |
| _tokens | address[4] |  |
| initialAmounts | uint256[4] |  |
| _owner | address |  |
| _operator | address |  |
| _configManager | address |  |
| _weth | address |  |
| _vaultOwnerFeeBasisPoint | uint16 | Basis points of LP performance/collection fees routed to `_owner`        on proportional exits (max 10_000). **Locked at initialization** — there is no setter. |

### deposit

```solidity
function deposit(uint256[4] amounts, uint16 slippageBps) external payable returns (uint256 shares)
```

Deposit tokens and receive shares. Send ETH via msg.value to auto-wrap to WETH
        (msg.value must match amounts[wethIndex] exactly; only the proportional amount
         is wrapped — excess ETH is refunded directly without an unwrap round-trip).

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amounts | uint256[4] |  |
| slippageBps | uint16 | Slippage tolerance in basis points (e.g. 100 = 1%) applied to each LP        position's proportional deposit: amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000).        Must be ≤ 10000. Pass 0 to skip the amountMin floor. |

### deposit

```solidity
function deposit(uint256[4] amounts, uint16 slippageBps, address receiver) external payable returns (uint256 shares)
```

Deposit tokens from the caller and mint shares to `receiver`.

_Preserves gateway/account attribution while the caller supplies the tokens._

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

### withdraw

```solidity
function withdraw(uint256 shares, uint256[4] minAmounts, bool unwrap, address account) external returns (uint256[4] amounts)
```

Burn `account` shares and withdraw proportional tokens to the caller.

_If caller is not `account`, the caller must have sufficient share allowance.
     `account` only selects whose shares are burned; proceeds are sent to `msg.sender`, not
     to `account`._

### execute

```solidity
function execute(struct ISharedVault.Action[] actions) external
```

Execute one or more actions: strategy delegatecalls (LP) and/or direct swap calls.
        For strategy actions the vault tracks LP position changes.
        For swap actions the vault validates tokenIn/tokenOut are vault tokens and checks
        that the output meets minAmountOut.

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

Total shareholder-owned balances: idle tokens plus LP principal and net uncollected LP fees.

_Reports the NET value owned by shareholders, not gross LP value. For each tracked position the
     uncollected-fee portion is reduced by the platform fee and then the vault-owner fee (mirroring
     `SharedStrategyFeeConfig.performanceFeeConfig`; the combined rate is clamped to 10000 bps).
     LP principal and idle balances are never fee-charged. This matches the realized `withdraw()`
     flow, which collects fees first so the proportional idle distribution is already net-of-fee.
     Integrator notes:
     - Share price is `totalSupply() / getTotalBalances()`. Because `configManager.platformFeeBasisPoint()`
       is read live (never cached), changing the platform fee instantly reprices every vault's shares:
       existing depositors' per-share value moves the moment the fee changes.
     - This same net figure feeds `previewDeposit`, `getMinDepositAmounts`, and the gateway's deposit
       ratio math, so dashboards and valuation tooling should expect the net (lower) number, not gross._

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

Preview token amounts returned for burning `shares`, NET of LP exit fees.

_Returns the proportional share of (idle + LP principal + (1 − feeRate) × uncollected LP fees).
     The fee deduction uses the same clamp logic as `SharedStrategyFeeConfig.performanceFeeConfig`:
     `platformFeeBasisPoint` + `vaultOwnerFeeBasisPoint`, with the owner share silently clamped if
     the sum exceeds 10000. Principal exits incur no perf/platform fee.
     Callers should still apply an AMM-slippage margin when deriving `minAmounts` for `withdraw()`._

### getMinDepositAmounts

```solidity
function getMinDepositAmounts() external view returns (uint256[4] minAmounts)
```

Per-token minimum amounts required for a subsequent deposit.

_Returns zeros on first deposit (totalSupply == 0) because no proportional floor applies.
     For subsequent deposits each non-zero-balance slot returns
     `10 ** max(0, token.decimals() - configManager.minTokenPrecision())`.
     Slots whose total balance is zero must be deposited at exactly zero; their entry is 0._

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

_**Custody / trust:** When `operator` is non-zero, the position NFT is transferred from this vault
     to `operator`. The vault owner initiates `dropPosition` but **cannot** unilaterally retrieve the
     NFT on-chain afterward—only `recoverPosition`, callable by `operator` only, returns custody to the
     vault. There is no alternative on-chain path for the vault owner if the operator is unavailable or
     compromised (unlike the no-`operator` case: the NFT stays in the vault and may be recovered via
     `sweepERC721`). Assume the operator is trusted for NFT custody between drop and recover._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT position manager that issued the position |
| tokenId | uint256 | The position token ID to drop |

### recoverPosition

```solidity
function recoverPosition(address nfpm, uint256 tokenId, address strategy, address token0, address token1) external
```

Recover a previously dropped position back into vault tracking.
        Pulls the NFT from the operator (caller must have approved this vault as spender),
        re-adds the position to tracking, and re-enables LP valuation and proportional exits.
        The strategy must be whitelisted in ConfigManager (it is delegatecalled on deposits/withdrawals).

_`token0` and `token1` must match the pool’s currencies; both must be tokens configured on this vault
     (`isVaultToken`). Wrong addresses break LP valuation and proportional exits. The operator is trusted
     to supply the correct pair (validated on-chain against the vault token set)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT position manager that issued the position |
| tokenId | uint256 | The position token ID to recover |
| strategy | address | Whitelisted strategy to use for this position (must implement ISharedStrategy) |
| token0 | address | Pool token0 (must be a configured vault token) |
| token1 | address | Pool token1 (must be a configured vault token) |

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

_Set at initialization and immutable thereafter — there is no setter._

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

