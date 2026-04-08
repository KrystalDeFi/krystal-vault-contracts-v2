# Shared Vault Implementation Plan

## Context

The Shared Vault is a new vault type that combines **ERC20 share-based deposits** (like public vault) with
**strategy-based LP management** using swap aggregators (like private vault). It manages up to 4 ERC20 tokens
simultaneously with no principal token — shares represent proportional ownership of all idle tokens plus all active
LP positions. The vault owner has maximum permission with no ConfigManager restrictions (no minimumTvl, minimumRange,
TWAP, whitelisted pools).

**Key difference from public vault**: No single principal token. Multi-token deposits/withdrawals in current ratio.
Uses swap aggregator instead of OptimalSwapper. No validation restrictions.
**Key difference from private vault**: Has ERC20 shares for multiple depositors. Uses validated strategy calls instead
of raw multicall.

---

## Implementation Status

**Completed** — all features are implemented and all tests pass.

### Changes from original plan

1. **`INITIAL_SHARES = 10e18`**: First deposit always mints exactly 10e18 shares (not amount-scaled). Applies both to
   factory initialization and to `deposit()` when `totalSupply == 0`.

2. **`operator` is fixed at initialization**: `setOperator` was removed. The operator role is set once at
   `initialize(name, tokens, amounts, owner, _operator, configManager, weth)` and cannot be changed. Pass
   `address(0)` for a vault with no operator.

3. **`execute(Action[], PositionStrategyUpdate[])` signature**: The execute function takes two parameters:
   - `Action[] actions` — LP operations and swaps
   - `PositionStrategyUpdate[] strategyUpdates` — optional list of position→strategy pointer remappings applied
     atomically before actions run. Each update requires a whitelisted strategy and an already-tracked position.
     Emits `PositionStrategyMigrated`. Used to migrate a broken strategy and execute via the replacement in the same tx.

4. **`CallType` enum in `ISharedCommon`**: Three execution modes instead of `isStrategy bool`:
   - `DELEGATECALL` — strategy delegatecall via `ISharedStrategy.execute()`, returns `PositionChange[]`
   - `CALL` — direct call to a swap aggregator; validates tokenIn/tokenOut ∈ vault tokens, checks output delta
   - `CALL_WITH_POSITIONS` — raw call to an external contract that returns `PositionChange[]`; no token validation
     (the external contract manages its own token flow)

5. **ETH deposit efficiency**: `deposit()` accepts native ETH via `msg.value` and wraps only the proportional needed
   amount to WETH, refunding any excess as raw ETH. Factory `createVault` also handles ETH by wrapping the full
   `msg.value` up front (no partial-wrap complexity needed since amounts are exact there).

6. **Withdrawal slippage model**: Individual LP exits use `minAmount0=0, minAmount1=0` (no per-position guard) so a
   single tight position cannot DoS the entire withdrawal. Instead, a single `minAmounts[4]` aggregate guard at the
   `withdraw()` level catches total output falling below expectation. `previewWithdraw()` uses
   `_getTotalBalances()` (idle + LP) for accurate pre-tx estimates.

7. **Withdrawal: idle-snapshot + LP-exit pattern**: Idle balances are snapshotted *before* LP exits. Each LP's
   returned tokens are added in full (not re-diluted by shares/totalSupply). This fixes double-dilution: the
   withdrawer's share of idle tokens is `mulDiv(shares, idleBefore[i], totalSupply)` and LP exit returns are added
   wholesale. An `unwrap` flag in `withdraw()` converts WETH output to native ETH before sending.

8. **`vaultOwnerFeeBasisPoint`**: A per-vault basis-point fee (max 10,000) charged on LP exits and routed to the vault
   owner. Set by the vault owner via `setVaultOwnerFeeBasisPoint`. Passed to every `exitProportional` call alongside
   the platform fee from `configManager`.

9. **`depositProportional` in `ISharedStrategy`**: New method called via delegatecall from `deposit()` for each
   tracked LP position when `totalSupply > 0`. Tokens are split proportionally using the pre-deposit `totalBalances`
   snapshot: `toAdd = mulDiv(transferAmounts[i], posAmt, totalBalances[i])`. The delegatecall is only made when
   `toAdd0 > 0 || toAdd1 > 0`. If the strategy cannot increase liquidity (staked positions), it must return silently.

10. **`_addPosition` auto-updates strategy pointer**: If a strategy's `execute()` returns `isAdd=true` for an already-
    tracked `(nfpm, tokenId)`, the position's `strategy` field is overwritten to point at the calling strategy and
    `PositionStrategyMigrated` is emitted. Mirrors `Vault.sol`'s `_addAssets` pattern.

11. **`dropPosition(nfpm, tokenId)` escape hatch**: Owner-only function to forcibly remove a position from tracking
    without exiting liquidity. Emits `PositionDropped`. Used when a pool is permanently rugged or the NFPM itself is
    bricked and `strategyUpdates` cannot fix it. The NFT stays in the vault; `sweepERC721` can recover it afterward.

12. **Factory: `createVault` uses `Action[]`**: The multi-strategy creation overload accepts
    `ISharedVault.Action[] calldata actions` and calls `vault.execute(actions, new PositionStrategyUpdate[](0))` once.
    No `_operator` parameter — the factory `owner()` is passed as the vault's initial operator.

13. **Automator: `strategyUpdates` forwarded**: Both `executeWithAgentAllowance` and `executeWithUserOrder` accept
    `ISharedVault.PositionStrategyUpdate[] calldata strategyUpdates` and forward it to `vault.execute`.

14. **Automator: multisig EIP-1271 support**: The automator accepts EIP-1271 signatures (validated via
    `SignatureChecker.isValidSignatureNow`) in addition to EOA signatures, enabling multisig vault owners.

---

## Architecture Overview

```
SharedVault (ERC20 shares + strategy execution)
├── Up to 4 managed ERC20 tokens (no principal)
├── Up to 6 LP pairs (C(4,2)), infinite pool addresses per pair
├── Proportional deposit: idle split + existing LP positions topped up via depositProportional
├── Proportional withdraw: idle share + full LP exit returns (no double-dilution)
├── LP management via whitelisted targets (delegatecall) — validates pool tokens ∈ vault tokens
├── Token swaps via whitelisted targets (call) — validates tokenIn/tokenOut ∈ vault tokens
├── Multi-DEX: Uniswap V3, V4, Aerodrome, PancakeSwap (one strategy per DEX)
├── Roles: owner (manage + dropPosition), admin (execute), operator (sweep non-vault tokens only)
├── Position strategy migration: via execute() strategyUpdates param or auto-update on re-execute
├── Escape hatch: dropPosition() removes broken/rugged positions from tracking
└── SharedConfigManager (per-vault pause + unified target whitelist + caller whitelist + fee recipient)

SharedVaultAutomator (operator-controlled batch execution)
├── Two auth flows: AgentAllowance (long-lived) and UserOrder (one-time, same struct but consumed)
├── Both flows forward strategyUpdates to vault.execute
├── EIP-1271 multisig support via SignatureChecker
└── EIP-712 signing with AccessControl + Pausable
```

---

## File Structure

```
contracts/shared-vault/
  interfaces/
    ISharedCommon.sol              — CallType enum, all shared errors (incl. InvalidOperation, InvalidVaultOwnerFeeBasisPoint)
    ISharedVault.sol               — Vault interface: Position/Action/PositionStrategyUpdate structs + all events
    ISharedVaultFactory.sol        — Factory interface: two createVault overloads + DuplicateVaultName error
    ISharedConfigManager.sol       — Config interface (unified target whitelist, no separate strategy whitelist)
    ISharedStrategy.sol            — execute + exitProportional + depositProportional + getPositionAmounts
    ISharedVaultAutomator.sol      — Automator: executeWithAgentAllowance + executeWithUserOrder (both with strategyUpdates)
  core/
    SharedVault.sol                — Main vault: shares + execute + deposit proportional LP + withdraw idle-snapshot + position tracking
    SharedVaultFactory.sol         — Factory: Clones proxy, two createVault overloads (no _operator param)
    SharedConfigManager.sol        — Pause + unified target/caller whitelist + fee recipient
    SharedVaultAutomator.sol       — Operator-driven batch execution with EIP-712 auth + EIP-1271 multisig
  strategies/
    SharedV3Strategy.sol           — Uniswap V3 LP ops via V3Utils + depositProportional
    SharedV4Strategy.sol           — Uniswap V4 LP ops via V4Utils + depositProportional (Permit2 flow)
    SharedAerodromeStrategy.sol    — Aerodrome LP ops + gauge farming + depositProportional (skips staked)
    SharedPancakeV3Strategy.sol    — PancakeSwap V3 LP ops + MasterChef farming + depositProportional (skips staked)
  libraries/
    SharedNfpmProportionalExit.sol — Shared V3-family proportional exit logic
    SharedStrategyFeeConfig.sol    — Fee config helpers shared across strategies

contracts/common/libraries/strategies/
  AgentAllowanceStructHash.sol     — EIP-712 struct for both AgentAllowance and UserOrder flows
```

---

## Step 1: Interfaces

### 1a. `ISharedCommon.sol`

```solidity
interface ISharedCommon {
  enum CallType { DELEGATECALL, CALL, CALL_WITH_POSITIONS }

  error Unauthorized();
  error ZeroAddress();
  error InvalidAmount();
  error InvalidToken();
  error InvalidRatio();
  error VaultPaused();
  error InvalidTarget(address target);
  error InvalidStrategy(address strategy);
  error StrategyCallFailed();
  error SwapFailed();
  error InsufficientShares();
  error InsufficientOutput();
  error NoTokensConfigured();
  error DuplicateToken();
  error TokenNotConfigured();
  error CannotSweepVaultToken();
  error InvalidOperation();
  error LengthMismatch();
  error InvalidVaultOwnerFeeBasisPoint();
  error InvalidFeeBasisPoint();
}
```

### 1b. `ISharedConfigManager.sol`

No separate strategy whitelist — strategies and swap targets share a single `whitelistedTargets` mapping:

```solidity
interface ISharedConfigManager {
  function isVaultPaused() external view returns (bool);
  function feeRecipient() external view returns (address);
  function isWhitelistedTarget(address target) external view returns (bool);
  function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external;
  function isWhitelistedCaller(address caller) external view returns (bool);
  function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external;
  function setVaultPaused(bool _isVaultPaused) external;
  function setFeeRecipient(address newFeeRecipient) external;
}
```

### 1c. `ISharedStrategy.sol`

```solidity
interface ISharedStrategy {
  error InvalidPoolTokens();

  struct PositionChange {
    bool isAdd;
    address nfpm;
    uint256 tokenId;
    address token0;
    address token1;
  }

  function execute(bytes calldata data) external payable returns (PositionChange[] memory changes);

  function exitProportional(
    address nfpm, uint256 tokenId,
    uint256 shares, uint256 totalShares,
    uint256 minAmount0, uint256 minAmount1,
    uint16 vaultOwnerFeeBasisPoint
  ) external returns (PositionChange[] memory changes);

  /// @dev Called via delegatecall from deposit(). Staked positions must return silently.
  function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1) external;

  /// @dev Called via regular CALL (not staticcall) — view prevents state mutation but EVM opcode is CALL.
  function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);
}
```

### 1d. `ISharedVault.sol`

```solidity
interface ISharedVault is ISharedCommon {
  // events: VaultDeposit, VaultWithdraw, VaultExecute, SetVaultAdmin, SetVaultOperator,
  //         VaultOwnerChanged, VaultPausedUpdated, VaultOwnerFeeBasisPointUpdated,
  //         PositionStrategyMigrated, PositionDropped

  struct Position { address strategy; address nfpm; uint256 tokenId; address token0; address token1; }
  struct Action { address target; bytes data; CallType callType; }
  struct PositionStrategyUpdate { address nfpm; uint256 tokenId; address strategy; }

  function initialize(string calldata name, address[4] calldata tokens, uint256[4] calldata initialAmounts,
    address _owner, address _operator, address _configManager, address _weth) external;

  function deposit(uint256[4] calldata amounts, uint256 minShares) external payable returns (uint256 shares);
  function withdraw(uint256 shares, uint256[4] calldata minAmounts, bool unwrap) external returns (uint256[4] memory);

  /// @param strategyUpdates Applied atomically before actions. Empty array = no migrations.
  function execute(Action[] calldata actions, PositionStrategyUpdate[] calldata strategyUpdates) external;

  function dropPosition(address nfpm, uint256 tokenId) external; // onlyOwner

  // views: getTokens, getIdleBalances, getTotalBalances, getPositionCount, getPosition,
  //        previewDeposit, previewWithdraw, isVaultToken, vaultOwner, configManager, weth, tokenCount
  // owner: grantAdminRole, revokeAdminRole, setPaused, setVaultOwnerFeeBasisPoint, transferOwnership
  // operator: sweepTokens, sweepNativeToken, sweepERC721, sweepERC1155
}
```

### 1e. `ISharedVaultFactory.sol`

```solidity
interface ISharedVaultFactory is ISharedCommon {
  error DuplicateVaultName();
  event VaultCreated(address indexed owner, address indexed vault, string name);

  // Simple vault — caller becomes owner; no _operator param (factory owner() used)
  function createVault(string calldata name, address[4] calldata tokens,
    uint256[4] calldata initialAmounts) external payable returns (address vault);

  // Vault with post-init LP action — factory temporarily owns vault, transfers to caller after execute
  function createVault(string calldata name, address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    ISharedVault.Action[] calldata actions) external payable returns (address vault);

  function isVault(address vault) external view returns (bool);
}
```

**Note**: No `_operator` parameter on either overload. The factory's `owner()` is passed as the vault's initial operator.

### 1f. `ISharedVaultAutomator.sol`

```solidity
interface ISharedVaultAutomator is ISharedCommon {
  error InvalidSignature();
  error OrderCancelled();

  function executeWithAgentAllowance(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    ISharedVault.PositionStrategyUpdate[] calldata strategyUpdates,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external;

  function executeWithUserOrder(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    ISharedVault.PositionStrategyUpdate[] calldata strategyUpdates,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  function cancelOrder(bytes32 hash, bytes memory signature) external;
  function isOrderCancelled(bytes calldata signature) external view returns (bool);
  function grantOperator(address operator) external;
  function revokeOperator(address operator) external;
}
```

---

## Step 2: SharedConfigManager

Storage (simpler than originally planned — no strategies mapping):

```solidity
mapping(address => bool) public whitelistedTargets;  // strategies AND swap aggregators
mapping(address => bool) public whitelistedCallers;  // automator and other authorized callers
bool public isVaultPaused;
address public feeRecipient;
```

Initialize:
```solidity
function initialize(address _owner, address[] calldata _whitelistTargets,
  address[] calldata _whitelistCallers, address _feeRecipient) public initializer
```

---

## Step 3: SharedVault

**Inherits**: `ERC20PermitUpgradeable`, `PausableUpgradeable`, `ReentrancyGuard`, `ERC721Holder`,
`ERC1155Holder`, `IERC1271`, `ISharedVault`

### Storage Layout

```solidity
uint256 public constant SHARES_PRECISION = 1e18;
uint256 public constant INITIAL_SHARES = 10e18;

ISharedConfigManager public configManager;
address public vaultOwner;
address public vaultFactory;   // permanently authorized (factory-time strategy execution)
address public operator;       // fixed at initialize(); no post-deploy setter
address public weth;

uint16 public tokenCount;
address[4] public tokens;
mapping(address => bool) public isVaultToken;
mapping(address => bool) public admins;
uint16 public vaultOwnerFeeBasisPoint;  // max 10_000; routed to vaultOwner on LP exits

Position[] public positions;
mapping(bytes32 => uint256) internal positionIndex;  // keccak256(nfpm, tokenId) => index+1
```

### Roles

| Role                   | Who                  | Can Do                                                                      |
| ---------------------- | -------------------- | --------------------------------------------------------------------------- |
| **Owner**              | Vault creator        | execute, dropPosition, manage admins, transfer ownership, per-vault pause   |
| **Admin**              | Granted by owner     | execute                                                                     |
| **Factory**            | vaultFactory address | execute (permanently authorized for creation-time strategy init)            |
| **Operator**           | Fixed at init        | sweep non-vault tokens, sweep native, sweep ERC721/ERC1155                  |
| **Depositor**          | Anyone               | deposit, withdraw (based on shares held)                                    |
| **Whitelisted caller** | Via ConfigManager    | execute (used by automator)                                                 |

### Share Math

**First deposit** (`totalSupply == 0`):
```
shares = INITIAL_SHARES (10e18), regardless of deposit size
```

**Subsequent deposits** — minimum-ratio across all provided tokens (prevents cherry-picking reference token):
```
shares = min over i where totalBalances[i] > 0 and amounts[i] > 0:
    FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i])

transferAmounts[i] = FullMath.mulDiv(shares, totalBalances[i], currentTotalSupply)
require(amounts[i] >= transferAmounts[i])  // excess stays with depositor
require(amounts[i] == 0) for tokens where totalBalances[i] == 0
```

**Total balance** = idle + LP positions: `strategy.getPositionAmounts(nfpm, tokenId)` per position.

### Deposit Flow

```
1. Snapshot currentTotalSupply and totalBalances (pre-deposit)
2. Compute shares and transferAmounts (minimum-ratio; INITIAL_SHARES on first deposit)
3. Wrap ETH → WETH if msg.value > 0 (only proportional needed amount; refund excess as raw ETH)
4. Transfer ERC20 transferAmounts from depositor
5. If currentTotalSupply > 0 and positions.length > 0:
   For each tracked position:
     (posAmt0, posAmt1) = strategy.getPositionAmounts(nfpm, tokenId)
     toAdd0 = mulDiv(transferAmounts[token0Idx], posAmt0, totalBalances[token0Idx])
     toAdd1 = mulDiv(transferAmounts[token1Idx], posAmt1, totalBalances[token1Idx])
     if toAdd0 > 0 or toAdd1 > 0:
       delegatecall strategy.depositProportional(nfpm, tokenId, toAdd0, toAdd1)
       (revert propagates — broken strategy blocks deposits; use dropPosition() to unblock)
6. _mint(depositor, shares)
```

### Withdrawal Flow

```
1. _burn(depositor, shares) — BEFORE LP exits
2. Snapshot idleBefore[4] — BEFORE LP exits
3. For each tracked position (swap-with-last on removal):
   delegatecall strategy.exitProportional(nfpm, tokenId, shares, totalSupply, 0, 0, vaultOwnerFeeBasisPoint)
   if result contains isAdd=false: _removePosition
4. For each token:
   lpExitReturn = IERC20(token).balanceOf(this) - idleBefore[i]
   amounts[i] = mulDiv(shares, idleBefore[i], currentTotalSupply) + lpExitReturn
   // idle proportion + full LP return (no double-dilution)
   require(amounts[i] >= minAmounts[i])
5. Transfer amounts (unwrap WETH → ETH if unwrap=true)
```

### Execute Flow

```
// strategyUpdates applied first (atomic migration):
For each update: require whitelisted + tracked; set positions[idx].strategy; emit PositionStrategyMigrated

// Then actions:
DELEGATECALL: delegatecall to strategy.execute(data) → _applyPositionChanges
CALL:         validate tokenIn/tokenOut ∈ vault tokens; safeResetAndApprove; call(swapCalldata); check output delta
CALL_WITH_POSITIONS: call(data) → _applyPositionChanges (no token validation)
```

### Position Tracking

`_addPosition`: if position already tracked, overwrites `strategy` field and emits `PositionStrategyMigrated`
(mirrors `Vault.sol`'s `_addAssets` pattern — re-executing via a new strategy auto-migrates the pointer).

`_removePosition`: swap-with-last pattern; `delete positionIndex[key]`.

`dropPosition`: `onlyOwner`; removes from tracking without exiting liquidity; emits `PositionDropped`.
Use when pool is rugged or NFPM is bricked and `strategyUpdates` cannot fix it.
Follow with `sweepERC721` to recover the NFT.

---

## Step 4: Strategies

### Strategy Pattern

```solidity
contract SharedXxxStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    // 1. Decode operation type + params
    // 2. Validate: ISharedVault(address(this)).isVaultToken(token0/token1)
    // 3. Execute LP operation
    // 4. Return PositionChange[]
  }

  function exitProportional(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares,
    uint256 minAmount0, uint256 minAmount1, uint16 vaultOwnerFeeBasisPoint)
    external override returns (PositionChange[] memory changes) { ... }

  function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1)
    external override { ... }  // staked positions must return silently

  function getPositionAmounts(address nfpm, uint256 tokenId)
    external view override returns (uint256, uint256) { ... }
}
```

Token validation pattern (inside strategy, running via delegatecall — `address(this)` is the vault):
```solidity
require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
```

### 4a. `SharedV3Strategy.sol` — Universal V3-family strategy

Wraps `V3Utils`. Operations: `SWAP_AND_MINT`, `SWAP_AND_INCREASE`, `SAFE_TRANSFER_NFT`, `CHANGE_RANGE`.

Handles all V3-compatible AMMs via the `protocol` flag in `SwapAndMintParams` / `Instructions`
(Uniswap V3, PancakeSwap V3 base, Aerodrome CL base, QuickSwap, etc.).

`exitProportional`: `WITHDRAW_AND_COLLECT_AND_SWAP` with `targetToken=address(0)` (no swap). Full exit returns
`PositionChange(false)`.

`depositProportional`: `safeResetAndApprove` → `INFPM.increaseLiquidity`. No staking check needed (V3Strategy
is only used for unstaked positions).

### 4b. `SharedV4Strategy.sol` — Uniswap V4

Wraps `V4UtilsRouter`. Operations: `EXECUTE` (generic V4Utils execute call), `SAFE_TRANSFER_NFT`.

`exitProportional`: Approves V4UtilsRouter for NFT → calls `DECREASE_AND_SWAP` with `swapDestToken=address(0)`.
V4Utils sweeps tokens back to vault; NFT returned to vault after processing.

`depositProportional`: Permit2 flow —
```
require(amounts ≤ type(uint160).max)
permit2Addr = IPermit2Addr(posm).permit2()
safeResetAndApprove(token, permit2Addr, amount)
IPermit2Allowance(permit2Addr).approve(token, posm, uint160(amount), deadline)
// then: INCREASE_LIQUIDITY_FROM_DELTAS (0x04) + CLOSE_CURRENCY (0x12) × 2
pm.modifyLiquidities(abi.encode(actions, params), deadline)
```

Uses local minimal interfaces `IPermit2Addr` and `IPermit2Allowance` (avoids `permit2/src/...` import path
that breaks the Solidity LSP).

### 4c. `SharedAerodromeStrategy.sol` — Aerodrome CL gauge farming

Only needed for gauge-specific operations: `SWAP_AND_MINT`, `SWAP_AND_INCREASE`, `SAFE_TRANSFER_NFT`,
`DEPOSIT_GAUGE`, `WITHDRAW_GAUGE`, `HARVEST_GAUGE`. Basic LP without gauge → use `SharedV3Strategy`.

`exitProportional`: Detects gauge staking via `ownerOf(tokenId) != address(this)`. If staked: harvests rewards,
`gauge.withdraw(tokenId)`, V3Utils proportional decrease. Partial exits re-stake via `gauge.approve + gauge.deposit`.

`depositProportional`: `ownerOf` guard (returns silently if staked). Otherwise `safeResetAndApprove` →
`INFPM.increaseLiquidity`.

### 4d. `SharedPancakeV3Strategy.sol` — PancakeSwap V3 MasterChef farming

Only needed for MasterChef operations: `SWAP_AND_MINT`, `SWAP_AND_INCREASE`, `SAFE_TRANSFER_NFT`,
`DEPOSIT_MASTERCHEF`, `WITHDRAW_MASTERCHEF`, `HARVEST_MASTERCHEF`. Basic LP → use `SharedV3Strategy`.

`exitProportional`: Detects staking via `ownerOf(tokenId) != address(this)`. If staked: harvests CAKE,
`masterChefV3.withdraw(tokenId, address(this))`, V3Utils proportional decrease. Partial exits re-stake via
`safeTransferFrom(this, masterChefV3, tokenId)`.

`depositProportional`: `ownerOf` guard (returns silently if staked in MasterChef). Otherwise
`safeResetAndApprove` → `INFPM.increaseLiquidity`.

---

## Step 5: SharedVaultFactory

**Inherits**: `OwnableUpgradeable`, `PausableUpgradeable`, `Withdrawable`, `ISharedVaultFactory`

### Storage

```solidity
ISharedConfigManager public configManager;
address public vaultImplementation;
address public weth;
mapping(address => address[]) public vaultsByAddress;
address[] public allVaults;
mapping(address => bool) public isVaultAddress;
```

### createVault flows

**Simple** (no actions):
```
1. keccak256(name, msg.sender, "shared-1.0") salt — DuplicateVaultName if already exists
2. Wrap ETH → WETH if msg.value > 0 (full wrap, exact match to initialAmounts[wethIdx])
3. Transfer ERC20 initialAmounts to vault (pre-initialize)
4. vault.initialize(name, tokens, initialAmounts, msg.sender, factory.owner(), configManager, weth)
   // operator = factory.owner(); no _operator param to createVault
```

**With actions**:
```
1-3. Same as simple
4. vault.initialize(..., _owner=address(this), ...)  // factory owns vault temporarily
5. vault.execute(actions, new PositionStrategyUpdate[](0))
   // works because factory is permanently authorized in vault's onlyAuthorized
6. vault.transferOwnership(msg.sender)
```

---

## Step 6: SharedVaultAutomator

**Inherits**: `CustomEIP712("SharedVaultAutomator", "1.0")`, `AccessControl`, `Pausable`, `Withdrawable`

**Two auth flows** — both use `AgentAllowanceStructHash.AgentAllowance`:

- `executeWithAgentAllowance`: reusable; validated by expiry; not consumed
- `executeWithUserOrder`: one-time; `_cancelledOrder[keccak256(sig)] = true` *before* dispatch (replay-safe)

Both flows forward `strategyUpdates` to `vault.execute(actions, strategyUpdates)`.

**EIP-1271 multisig**: `SignatureChecker.isValidSignatureNow(vaultOwner, digest, sig)` — accepts both EOA ECDSA
and smart-wallet (EIP-1271) signatures. Vault `isValidSignature` delegates to `vaultOwner` automatically.

**Roles**: `DEFAULT_ADMIN_ROLE` for admin ops; `OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE")` for execution.

---

## Step 7: Deployment Scripts & Config

### `scripts/deployLogic-shared.ts`

Deploy sequence:
1. Deploy `SharedVault` implementation
2. Deploy `SharedConfigManager` (upgradeable proxy)
3. Deploy `SharedVaultFactory` (upgradeable proxy → initialize with configManager, vault impl, weth)
4. Deploy `SharedV3Strategy`
5. Deploy `SharedV4Strategy`
6. Deploy `SharedAerodromeStrategy`
7. Deploy `SharedPancakeV3Strategy`
8. Deploy `SharedVaultAutomator` (constructor: `_owner`, `_operators`)
9. Initialize `SharedConfigManager`:
   - `whitelistedTargets` = all 4 strategy addresses
   - `whitelistedCallers` = [automator address]
   - `feeRecipient` = `commonConfig.feeCollector`

### `configs/interfaces.ts`

`IConfigShared` extends `IConfig` with: `sharedVault`, `sharedVaultFactory`, `sharedConfigManager`,
`sharedV3Strategy`, `sharedV4Strategy`, `sharedAerodromeStrategy`, `sharedPancakeV3Strategy`,
`sharedVaultAutomator`.

---

## Step 8: Tests

### `test/unit/SharedVault.t.sol` — 75 tests

- Initialization, deposit (first/subsequent/proportional cap/ETH wrap/excess refund)
- Minimum-ratio share calculation; INITIAL_SHARES constant
- Proportional deposit into LP positions; `depositProportional` delegatecall
- `dropPosition`: happy path, unblocks deposit, fail-not-tracked, fail-unauthorized
- Withdrawal: idle-snapshot + LP exit, no double-dilution, aggregate minAmounts slippage, WETH unwrap
- `vaultOwnerFeeBasisPoint` forwarded to exitProportional
- `execute()` with DELEGATECALL, CALL (swap), CALL_WITH_POSITIONS
- `strategyUpdates` in execute: migration, unauthorized, not-whitelisted, not-tracked, unblocks-withdrawal
- Auto-update of `pos.strategy` when re-executing via new strategy
- Sweep (operator), reject vault tokens, reject non-operator
- Per-vault pause (alongside global configManager pause)
- Role management: admins, operator (fixed, no setter), ownership transfer
- EIP-1271 signature validation

### `test/unit/SharedVaultFactory.t.sol` — 20 tests

- Simple and action-based vault creation
- ETH wrapping for initial deposit; wrong amount rejects
- `DuplicateVaultName` guard
- `MockFactoryStrategy` tracks execution via `PositionChange` return (not storage — delegatecall writes to vault)
- Operator = factory.owner() after creation

### `test/unit/SharedVaultAutomator.t.sol` — 23 tests

- Both auth flows (agentAllowance, userOrder) with EOA and EIP-1271 multisig signatures
- One-time use enforcement for userOrder (replay reverts)
- Manual cancellation via `cancelOrder`
- Wrong vault/signer/expiry reverts with `InvalidSignature`
- `strategyUpdates` forwarded correctly
- Pause/unpause, role management

---

## Reuse Summary

| Component                     | Source                                         | How Used                                              |
| ----------------------------- | ---------------------------------------------- | ----------------------------------------------------- |
| `FullMath`                    | `@uniswap/v3-core`                             | Share math (mulDiv)                                   |
| `SafeERC20`                   | OpenZeppelin                                   | Token transfers                                       |
| `SafeApprovalLib`             | `private-vault/libraries/SafeApprovalLib.sol`  | USDT-safe approve reset in strategies                 |
| `ERC20PermitUpgradeable`      | OpenZeppelin                                   | Share token with EIP-2612                             |
| `Clones`                      | OpenZeppelin                                   | Deterministic proxy deployment                        |
| `Withdrawable`                | `contracts/common/Withdrawable.sol`            | Factory + automator sweep functions                   |
| `SignatureChecker`            | OpenZeppelin                                   | EIP-1271 validation in automator                      |
| `AgentAllowanceStructHash`    | `common/libraries/strategies/`                 | EIP-712 for both agentAllowance and userOrder flows   |
| `CustomEIP712`                | `private-vault/core/CustomEIP712.sol`          | Domain separator + `_recoverAgentAllowance`           |
| `IV3Utils` structs            | `private-vault/interfaces/strategies/lpv3/`    | SwapAndMintParams, Instructions, etc.                 |
| `IV4UtilsRouter`              | `private-vault/interfaces/strategies/lpv4/`    | V4 execution interface                                |
| `SharedNfpmProportionalExit`  | `shared-vault/libraries/`                      | Shared V3-family exit logic across strategies         |
| `SharedStrategyFeeConfig`     | `shared-vault/libraries/`                      | Fee config helpers shared across strategies           |

---

## Verification

1. `forge build` — all contracts compile without errors ✓
2. `forge test --match-contract SharedVaultTest` — 75 unit tests pass ✓
3. `forge test --match-contract SharedVaultFactoryTest` — 20 unit tests pass ✓
4. `forge test --match-contract SharedVaultAutomatorTest` — 23 unit tests pass ✓

Total: **118 unit tests** passing.

Integration tests (`test/integration/Integration.SharedVault*.t.sol`) require fork RPC URLs and cover:
- Uniswap V3: swapAndMint, swapAndIncrease, collectFees, fullWithdraw, proportional deposit with active LP
- ETH deposit/unwrap withdraw
- Factory createVault with initial LP position
- Aerodrome: gauge deposit/withdraw/harvest + proportional exit
- PancakeSwap V3: MasterChef deposit/withdraw/harvest + proportional exit
- Multi-protocol: mixed V3/V4/Aerodrome positions in a single vault
