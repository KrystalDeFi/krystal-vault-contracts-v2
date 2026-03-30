# Shared Vault Implementation Plan

## Context

The Shared Vault is a new vault type that combines **ERC20 share-based deposits** (like public vault) with
**strategy-based LP management** using swap aggregators (like private vault). It manages up to 4 ERC20 tokens
simultaneously with no principal token — shares represent proportional ownership of all idle tokens. The vault owner has
maximum permission with no ConfigManager restrictions (no minimumTvl, minimumRange, TWAP, whitelisted pools).

**Key difference from public vault**: No single principal token. Multi-token deposits/withdrawals in current ratio. Uses
swap aggregator instead of OptimalSwapper. No validation restrictions. **Key difference from private vault**: Has ERC20
shares for multiple depositors. Uses validated strategy calls instead of raw multicall.

---

## Architecture Overview

```
SharedVault (ERC20 shares + strategy execution)
├── Up to 4 managed ERC20 tokens (no principal)
├── Up to 6 LP pairs (C(4,2)), infinite pool addresses per pair
├── Proportional deposit/withdraw across all tokens
├── LP management via whitelisted targets (delegatecall) — validates pool tokens ∈ vault tokens
├── Token swaps via whitelisted targets (call) — validates tokenIn/tokenOut ∈ vault tokens
├── Multi-DEX: Uniswap V3, V4, Aerodrome, PancakeSwap (one strategy per DEX)
├── Roles: owner (manage), admin (execute), operator (sweep non-vault tokens only)
└── SharedConfigManager (per-vault pause + unified target whitelist + caller whitelist + fee recipient)

SharedVaultAutomator (operator-controlled batch execution)
├── Two auth flows: AgentAllowance (long-lived) and UserOrder (one-time, same struct but consumed)
├── Typed Operations: EXECUTE (delegatecall strategy) + SWAP (token swap)
└── EIP-712 signing with AccessControl + Pausable
```

---

## File Structure

```
contracts/shared-vault/
  interfaces/
    ISharedCommon.sol              — Common types, errors, enums
    ISharedVault.sol               — Vault interface with events
    ISharedVaultFactory.sol        — Factory interface
    ISharedConfigManager.sol       — Config interface (unified target whitelist, no separate strategy whitelist)
    ISharedStrategy.sol            — Strategy interface for LP operations
    ISharedVaultAutomator.sol      — Automator interface
  core/
    SharedVault.sol                — Main vault: shares + strategy execution + swap + position tracking
    SharedVaultFactory.sol         — Factory using Clones proxy, supports multi-strategy init
    SharedConfigManager.sol        — Pause + unified target/caller whitelist + fee recipient
    SharedVaultAutomator.sol       — Operator-driven batch execution with EIP-712 auth
  strategies/
    SharedV3Strategy.sol           — Uniswap V3 LP ops via V3Utils + token validation
    SharedV4Strategy.sol           — Uniswap V4 LP ops via V4Utils + token validation
    SharedAerodromeStrategy.sol    — Aerodrome LP ops + token validation
    SharedPancakeV3Strategy.sol    — PancakeSwap V3 LP ops + token validation

contracts/common/libraries/strategies/
  AgentAllowanceStructHash.sol     — EIP-712 struct for both AgentAllowance and UserOrder flows
  (SharedVaultOrderStructHash.sol was created then removed — AgentAllowanceStructHash reused for both)
```

Plus deployment scripts and config extensions.

---

## Step 1: Interfaces

### 1a. `contracts/shared-vault/interfaces/ISharedCommon.sol`

```solidity
interface ISharedCommon {
    error Unauthorized();
    error ZeroAddress();
    error InvalidAmount();
    error InvalidToken();
    error InvalidRatio();
    error VaultPaused();
    error InvalidTarget(address target);
    error LengthMismatch();
    error StrategyCallFailed();
    error SwapFailed();
    error InsufficientShares();
    error InsufficientOutput();
    error NoTokensConfigured();
    error DuplicateToken();
    error TokenNotConfigured();
    error CannotSweepVaultToken();
}
```

**Note**: `InvalidStrategy` was removed — strategies now use the same `isWhitelistedTarget` check as swap aggregators.

### 1b. `contracts/shared-vault/interfaces/ISharedConfigManager.sol`

**Actual implementation** — no separate strategy whitelist. Strategies and swap targets share a single
`whitelistedTargets` mapping:

```solidity
interface ISharedConfigManager {
    event FeeRecipientUpdated(address previousRecipient, address newRecipient);
    event WhitelistTargetsUpdated(address[] targets, bool isWhitelisted);
    event WhitelistCallersUpdated(address[] callers, bool isWhitelisted);
    event VaultPausedUpdated(bool isVaultPaused);

    function isVaultPaused() external view returns (bool);
    function feeRecipient() external view returns (address);

    // Unified target whitelist (for both strategy delegatecalls AND swap aggregator calls)
    function isWhitelistedTarget(address target) external view returns (bool);
    function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external;

    // Caller whitelist (authorized callers besides owner/admin — used for automator)
    function isWhitelistedCaller(address caller) external view returns (bool);
    function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external;

    function setVaultPaused(bool _isVaultPaused) external;
    function setFeeRecipient(address newFeeRecipient) external;
}
```

**Design decision**: `whitelistedStrategies` was originally separate but was removed during code review. Both strategies
(delegatecall targets) and swap aggregators (call targets) use the same `isWhitelistedTarget` check. This simplifies the
config manager significantly.

### 1c. `contracts/shared-vault/interfaces/ISharedStrategy.sol`

Common interface for all shared vault strategies. Strategies validate that pool tokens are among the vault's managed
tokens. Returns `PositionChange[]` for vault position tracking:

```solidity
interface ISharedStrategy {
    error InvalidPoolTokens();

    struct PositionChange {
        bool isAdd;       // true = add position, false = remove
        address nfpm;     // NFT Position Manager address
        uint256 tokenId;  // Position NFT token ID
        address token0;   // Pool token0
        address token1;   // Pool token1
    }

    /// @notice Execute an LP operation. Called via delegatecall from SharedVault.
    /// @dev Strategy MUST validate that pool tokens are vault tokens.
    ///      Since this runs via delegatecall, address(this) is the vault.
    function execute(bytes calldata data) external payable returns (PositionChange[] memory changes);

    function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);
}
```

**Token validation pattern** (used inside each strategy):

```solidity
// Inside strategy, running via delegatecall — address(this) is the vault
function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
}
```

### 1d. `contracts/shared-vault/interfaces/ISharedVault.sol`

```solidity
interface ISharedVault is ISharedCommon {
    // ... events ...

    // --- Initialization (no symbol — uses name for both ERC20 name and symbol) ---
    function initialize(
        string calldata name,
        address[4] calldata _tokens,
        uint256[4] calldata initialAmounts,
        address _owner,
        address _configManager
    ) external;

    // --- Deposit / Withdraw (anyone) ---
    function deposit(uint256[4] calldata amounts, uint256 minShares) external returns (uint256 shares);
    function withdraw(uint256 shares, uint256[4] calldata minAmounts) external returns (uint256[4] memory amounts);

    // --- LP Operations (onlyAuthorized) ---
    function execute(address strategy, bytes calldata data) external payable;
    function swap(address swapTarget, address tokenIn, address tokenOut,
        uint256 amountIn, uint256 minAmountOut, bytes calldata swapData) external;

    // --- Views ---
    function getTokens() external view returns (address[4] memory);
    function getIdleBalances() external view returns (uint256[4] memory);
    function getPositionCount() external view returns (uint256);
    function getPosition(uint256 index) external view returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1);
    function previewDeposit(uint256[4] calldata amounts) external view returns (uint256 shares);
    function previewWithdraw(uint256 shares) external view returns (uint256[4] memory amounts);
    function isVaultToken(address token) external view returns (bool);
    function vaultOwner() external view returns (address);
    function tokenCount() external view returns (uint8);
}
```

### 1e. `contracts/shared-vault/interfaces/ISharedVaultFactory.sol`

```solidity
interface ISharedVaultFactory is ISharedCommon {
    function createVault(
        string calldata name,
        address[4] calldata tokens,
        uint256[4] calldata initialAmounts
    ) external returns (address vault);

    // Multi-strategy variant: executes strategies sequentially after vault creation
    function createVault(
        string calldata name,
        address[4] calldata tokens,
        uint256[4] calldata initialAmounts,
        address[] calldata strategies,
        bytes[] calldata strategiesData,
        uint256[] calldata ethValues
    ) external payable returns (address vault);

    function isVault(address vault) external view returns (bool);
}
```

**Note**: `symbol` parameter was removed — `__ERC20_init(_name, _name)` uses name for both.

### 1f. `contracts/shared-vault/interfaces/ISharedVaultAutomator.sol`

```solidity
interface ISharedVaultAutomator is ISharedCommon {
    error InvalidSignature();
    error OrderCancelled();
    event CancelOrder(address user, bytes32 hash, bytes signature);

    enum OpType { EXECUTE, SWAP }

    struct Operation {
        OpType opType;
        address target;   // strategy for EXECUTE, swap aggregator for SWAP
        bytes data;       // strategy data for EXECUTE; abi.encode(tokenIn,tokenOut,amountIn,minAmountOut,swapData) for SWAP
        uint256 value;    // ETH forwarded (EXECUTE only; 0 for SWAP)
    }

    // Long-lived authorization — reusable until expiry
    function executeWithAgentAllowance(ISharedVault vault, Operation[] calldata operations,
        bytes memory abiEncodedAgentAllowance, bytes memory signature) external payable;

    // One-time authorization — same AgentAllowance struct but signature is consumed after use
    function executeWithUserOrder(ISharedVault vault, Operation[] calldata operations,
        bytes calldata abiEncodedAgentAllowance, bytes calldata signature) external payable;

    function cancelOrder(bytes32 hash, bytes memory signature) external;
    function isOrderCancelled(bytes calldata signature) external view returns (bool);
    function grantOperator(address operator) external;
    function revokeOperator(address operator) external;
}
```

---

## Step 2: SharedConfigManager

### `contracts/shared-vault/core/SharedConfigManager.sol`

**Actual storage** (simpler than originally planned — no strategies mapping):

```solidity
mapping(address => bool) public whitelistedTargets;  // strategies AND swap aggregators
mapping(address => bool) public whitelistedCallers;  // automator and other authorized callers
bool public isVaultPaused;
address public feeRecipient;
```

**Initialize signature**:

```solidity
function initialize(
    address _owner,
    address[] calldata _whitelistTargets,   // includes both strategies and swap targets
    address[] calldata _whitelistCallers,   // includes automator address
    address _feeRecipient
) public initializer
```

---

## Step 3: SharedVault

### `contracts/shared-vault/core/SharedVault.sol`

**Inherits**: `ERC20PermitUpgradeable`, `ReentrancyGuard`, `ERC721Holder`, `ERC1155Holder`, `IERC1271`, `ISharedVault`

### Storage Layout

```solidity
uint256 public constant SHARES_PRECISION = 1e18;

ISharedConfigManager public configManager;
address public override vaultOwner;
address public vaultFactory;       // permanently authorized (for factory-time strategy execution)
address public operator;

uint8 public override tokenCount;
address[4] public tokens;
mapping(address => bool) public isVaultToken;
mapping(address => bool) public admins;
bool public paused;               // per-vault pause (in addition to global configManager.isVaultPaused)

struct Position {
    address strategy;
    address nfpm;
    uint256 tokenId;
    address token0;
    address token1;
}
Position[] public positions;
mapping(bytes32 => uint256) internal positionIndex;  // keccak256(nfpm, tokenId) => index+1
```

### Roles

| Role                   | Who                  | Can Do                                                                     |
| ---------------------- | -------------------- | -------------------------------------------------------------------------- |
| **Owner**              | Vault creator        | execute, swap, manage admins/operator, transfer ownership, per-vault pause |
| **Admin**              | Granted by owner     | execute, swap                                                              |
| **Factory**            | vaultFactory address | execute, swap (permanently authorized for creation-time strategy init)     |
| **Operator**           | Set by owner         | sweep non-vault tokens, sweep native, sweep ERC721/ERC1155                 |
| **Depositor**          | Anyone               | deposit, withdraw (based on shares held)                                   |
| **Whitelisted caller** | Via ConfigManager    | execute, swap (used by automator)                                          |

### Modifiers

```solidity
modifier onlyOwner()      — msg.sender == vaultOwner
modifier onlyAuthorized() — vaultOwner OR vaultFactory OR admins[msg.sender] OR configManager.isWhitelistedCaller
modifier onlyOperator()   — msg.sender == operator
modifier whenNotPaused()  — !paused && !configManager.isVaultPaused()
```

**Note**: `vaultFactory` is included in `onlyAuthorized` so the factory can execute strategies during vault creation in
the multi-strategy `createVault` overload.

### Share Math — Minimum-Ratio Approach

**Shares represent `shares / totalSupply` fraction of every token's TOTAL balance (idle + LP positions).**

**First deposit** (`totalSupply == 0`):

```
shares = amounts[refIndex] * SHARES_PRECISION
// refIndex = first token with amounts[i] > 0
```

**Subsequent deposits** (`totalSupply > 0`) — minimum-ratio across all provided tokens:

```
shares = type(uint256).max
for each token i with totalBalance[i] > 0 AND amounts[i] > 0:
    s = FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalance[i])
    if s < shares: shares = s

// Transfer only the proportional amount; excess stays with depositor
for each token i with totalBalance[i] > 0:
    transferAmount[i] = FullMath.mulDiv(shares, totalBalance[i], currentTotalSupply)
    require(amounts[i] >= transferAmount[i])
for tokens with totalBalance[i] == 0:
    require(amounts[i] == 0)
```

**Security rationale**: The minimum-ratio approach prevents a depositor from cherry-picking a reference token to receive
disproportionate shares via integer rounding. It also allows overproviding any token (excess stays with depositor),
matching standard AMM behavior.

**Total balance** = idle + LP positions (valued via `strategy.getPositionAmounts(nfpm, tokenId)`).

**Withdrawal**:

```
currentTotalSupply = totalSupply()  // capture BEFORE burn
_burn(msg.sender, shares)
For each active token i:
    amounts[i] = FullMath.mulDiv(shares, idleBalance[i], currentTotalSupply)
    // Note: withdrawal only returns IDLE balances; LP positions must be unwound separately
    transfer amounts[i] to msg.sender
```

### Execute Flow (LP Operations)

```
function execute(address strategy, bytes calldata data) external payable onlyAuthorized whenNotPaused nonReentrant {
    1. require(configManager.isWhitelistedTarget(strategy), InvalidTarget)   // unified check
    2. (bool success, bytes memory result) = strategy.delegatecall(
           abi.encodeCall(ISharedStrategy.execute, (data))
       )
    3. if (!success) revert with original error
    4. Decode PositionChange[] from result and update positions tracking
    5. emit VaultExecute(vaultFactory, strategy, data)
}
```

### Swap Flow

```
function swap(address swapTarget, address tokenIn, address tokenOut,
              uint256 amountIn, uint256 minAmountOut, bytes calldata swapData)
    external onlyAuthorized whenNotPaused nonReentrant {
    1. require(isVaultToken[tokenIn], TokenNotConfigured)
    2. require(isVaultToken[tokenOut], TokenNotConfigured)
    3. require(configManager.isWhitelistedTarget(swapTarget), InvalidTarget)
    4. uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this))
    5. IERC20(tokenIn).safeResetAndApprove(swapTarget, amountIn)
    6. (bool success, ) = swapTarget.call(swapData)
    7. require(success, SwapFailed)
    8. amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore
    9. require(amountOut >= minAmountOut, InsufficientOutput)
   10. emit VaultSwap(...)
}
```

---

## Step 4: Strategies

Each strategy wraps an existing external protocol and adds **token validation** + returns `PositionChange[]` for vault
position tracking.

### Strategy Pattern

```solidity
contract SharedXxxStrategy is ISharedStrategy {
    function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
        // 1. Decode operation type + params
        // 2. Extract pool token0/token1
        // 3. Validate: ISharedVault(address(this)).isVaultToken(token0/token1)
        // 4. Execute LP operation
        // 5. Return PositionChange[] for vault tracking
    }

    function getPositionAmounts(address nfpm, uint256 tokenId) external view override returns (uint256, uint256) {
        // Used by vault for share valuation
    }
}
```

### 4a. `SharedV3Strategy.sol` — Uniswap V3

Wraps `V3Utils`. Operations: `SWAP_AND_MINT`, `SWAP_AND_INCREASE`, `SAFE_TRANSFER_NFT`.

### 4b. `SharedV4Strategy.sol` — Uniswap V4

Wraps `V4UtilsRouter`. Operations: `INCREASE_LIQUIDITY`, `DECREASE_LIQUIDITY`, `COLLECT`, `MINT`, `BURN`, `SETTLE`,
`SETTLE_ALL`, `TAKE`, `TAKE_ALL`, `CLOSE_CURRENCY`, `SWEEP`.

### 4c. `SharedAerodromeStrategy.sol` — Aerodrome

Wraps `V3Utils` with Aerodrome protocol flag. Operations: same as V3 + `DEPOSIT_GAUGE`, `WITHDRAW_GAUGE`,
`HARVEST_GAUGE`.

### 4d. `SharedPancakeV3Strategy.sol` — PancakeSwap V3

Wraps `V3Utils` with PancakeSwap support + MasterChef farming. Operations: same as V3 + `DEPOSIT_MASTERCHEF`,
`WITHDRAW_MASTERCHEF`, `HARVEST_MASTERCHEF`.

---

## Step 5: SharedVaultFactory

### `contracts/shared-vault/core/SharedVaultFactory.sol`

**Salt**: `keccak256(abi.encodePacked(name, msg.sender, "shared-1.0"))` — symbol removed.

**Multi-strategy create flow**:

```
1. Validate strategies.length == strategiesData.length == ethValues.length
2. Validate sum(ethValues) == msg.value
3. Clone vault deterministically
4. Transfer initial tokens to vault (before initialize)
5. ISharedVault(vault).initialize(name, tokens, initialAmounts, msg.sender, configManager)
6. For each strategy i:
   ISharedVault(vault).execute{value: ethValues[i]}(strategies[i], strategiesData[i])
   // Works because factory is permanently authorized in vault's onlyAuthorized
```

---

## Step 6: SharedVaultAutomator

### `contracts/shared-vault/core/SharedVaultAutomator.sol`

**Inherits**: `CustomEIP712("SharedVaultAutomator", "1.0")`, `AccessControl`, `Pausable`, `Withdrawable`

**Two auth flows — both use `AgentAllowanceStructHash.AgentAllowance`**:

- `executeWithAgentAllowance`: reusable, validated by expiry, not consumed
- `executeWithUserOrder`: one-time, same struct but `_cancelledOrder[sig] = true` before execution

**Key design decisions**:

- Both flows use the same `AgentAllowanceStructHash` (no separate `SharedVaultOrderStructHash`) — one-time vs reusable
  is a behavioral distinction, not a structural one
- `_cancelledOrder` keyed by `keccak256(signature)`, not by digest — allows same allowance to be signed multiple times
  with different sigs
- Mark consumed **before** dispatching operations (prevents reentrancy replay)
- ETH validation (`sum(op.value for EXECUTE ops) == msg.value`) in a separate pass before execution
- `SWAP` op data encoded as `abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapData)`

**Roles**: `DEFAULT_ADMIN_ROLE` for admin operations; `OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE")` for execution.

---

## Step 7: Deployment Scripts & Config

### `scripts/deployLogic-shared.ts`

Deploy sequence:

1. Deploy `SharedVault` implementation
2. Deploy `SharedConfigManager` (upgradeable proxy)
3. Deploy `SharedVaultFactory` (upgradeable proxy → initialize with configManager + vault impl)
4. Deploy `SharedV3Strategy`
5. Deploy `SharedV4Strategy`
6. Deploy `SharedAerodromeStrategy`
7. Deploy `SharedPancakeV3Strategy`
8. Deploy `SharedVaultAutomator` (constructor: `_owner`, `_operators`)
9. Initialize `SharedConfigManager`:
   - `whitelistedTargets` = all 4 strategy addresses (strategies and swap targets share the same list)
   - `whitelistedCallers` = [automator address]
   - `feeRecipient` = `commonConfig.feeCollector`

**Note**: The original plan had `whitelistedStrategies` as a separate first argument to `initialize`. In the actual
implementation, strategies go into `whitelistedTargets` — there is no separate strategies array.

### `configs/interfaces.ts`

`IConfigShared` extends `IConfig` with: `sharedVault`, `sharedVaultFactory`, `sharedConfigManager`, `sharedV3Strategy`,
`sharedV4Strategy`, `sharedAerodromeStrategy`, `sharedPancakeV3Strategy`, `sharedVaultAutomator`.

---

## Step 8: Tests

### `test/unit/SharedVault.t.sol`

- Initialization, deposit (first/subsequent/proportional cap), withdrawal
- Minimum-ratio share calculation (not reference-token based)
- `setOperator(address(0))` rejects with `ZeroAddress`
- Execute via whitelisted target, Unauthorized, InvalidTarget
- Swap between vault tokens
- Sweep (operator), reject vault tokens, reject non-operator
- Per-vault pause (alongside global pause)
- Role management

### `test/unit/SharedVaultFactory.t.sol`

- Simple and multi-strategy vault creation
- ETH validation for multi-strategy variant
- `MockFactoryStrategy` tracks execution via `PositionChange` return (not storage — delegatecall writes to vault
  storage)

### `test/unit/SharedVaultAutomator.t.sol`

- Both auth flows (agentAllowance, userOrder)
- One-time use enforcement for userOrder
- Manual cancellation
- Wrong vault/signer/expiry revert with `InvalidSignature`
- ETH mismatch reverts with `InvalidAmount`
- Pause/unpause, role management

---

## Reuse Summary

| Component                     | Source                                         | How Used                                            |
| ----------------------------- | ---------------------------------------------- | --------------------------------------------------- |
| `FullMath`                    | `@uniswap/v3-core`                             | Share math (mulDiv)                                 |
| `SafeERC20`                   | OpenZeppelin                                   | Token transfers                                     |
| `SafeApprovalLib`             | `private-vault/libraries/SafeApprovalLib.sol`  | USDT approve(0) in strategies & swap                |
| `ERC20PermitUpgradeable`      | OpenZeppelin                                   | Share token with EIP-2612                           |
| `Clones`                      | OpenZeppelin                                   | Deterministic proxy deployment                      |
| `Withdrawable`                | `contracts/common/Withdrawable.sol`            | Factory + automator sweep functions                 |
| `SignatureChecker`            | OpenZeppelin                                   | IERC1271 support                                    |
| `AgentAllowanceStructHash`    | `common/libraries/strategies/`                 | EIP-712 for BOTH agentAllowance and userOrder flows |
| `CustomEIP712`                | `private-vault/core/CustomEIP712.sol`          | Domain separator + `_recoverAgentAllowance`         |
| `IV3Utils` structs            | `private-vault/interfaces/strategies/lpv3/`    | SwapAndMintParams, Instructions, etc.               |
| `IV4UtilsRouter`              | `private-vault/interfaces/strategies/lpv4/`    | V4 execution interface                              |
| PrivateVaultAutomator pattern | `private-vault/core/PrivateVaultAutomator.sol` | Auth flows, operation dispatch                      |

---

## Verification

1. `forge build` — all contracts compile without errors
2. `forge test --match-contract SharedVault` — unit tests pass
3. `forge test --match-contract SharedVaultFactory` — unit tests pass
4. `forge test --match-contract SharedVaultAutomator` — unit tests pass
5. Manual review: strategy token validation, share math edge cases, operator restrictions
