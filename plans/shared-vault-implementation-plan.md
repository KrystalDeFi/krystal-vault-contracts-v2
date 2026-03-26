# Shared Vault Implementation Plan

## Context

The Shared Vault is a new vault type that combines **ERC20 share-based deposits** (like public vault) with **strategy-based LP management** using swap aggregators (like private vault). It manages up to 4 ERC20 tokens simultaneously with no principal token — shares represent proportional ownership of all idle tokens. The vault owner has maximum permission with no ConfigManager restrictions (no minimumTvl, minimumRange, TWAP, whitelisted pools).

**Key difference from public vault**: No single principal token. Multi-token deposits/withdrawals in current ratio. Uses swap aggregator instead of OptimalSwapper. No validation restrictions.
**Key difference from private vault**: Has ERC20 shares for multiple depositors. Uses validated strategy calls instead of raw multicall.

---

## Architecture Overview

```
SharedVault (ERC20 shares + strategy execution)
├── Up to 4 managed ERC20 tokens (no principal)
├── Up to 6 LP pairs (C(4,2)), infinite pool addresses per pair
├── Proportional deposit/withdraw across all tokens
├── LP management via whitelisted strategies (delegatecall) — validates pool tokens ∈ vault tokens
├── Token swaps via whitelisted aggregator targets (call) — validates tokenIn/tokenOut ∈ vault tokens
├── Multi-DEX: Uniswap V3, V4, Aerodrome, PancakeSwap (one strategy per DEX)
├── Roles: owner (manage), admin (execute), operator (sweep non-vault tokens only)
└── Minimal SharedConfigManager (pause + strategy/target whitelist + fee recipient)
```

---

## File Structure

```
contracts/shared-vault/
  interfaces/
    ISharedCommon.sol              — Common types, errors, enums
    ISharedVault.sol               — Vault interface with events
    ISharedVaultFactory.sol        — Factory interface
    ISharedConfigManager.sol       — Config interface (strategy + target whitelist)
    ISharedStrategy.sol            — Strategy interface for LP operations
  core/
    SharedVault.sol                — Main vault: shares + strategy execution + swap
    SharedVaultFactory.sol         — Factory using Clones proxy
    SharedConfigManager.sol        — Pause + strategy/target/caller whitelist + fee recipient
  strategies/
    SharedV3Strategy.sol           — Uniswap V3 LP ops via V3Utils + token validation
    SharedV4Strategy.sol           — Uniswap V4 LP ops via V4Utils + token validation
    SharedAerodromeStrategy.sol    — Aerodrome LP ops + token validation
    SharedPancakeV3Strategy.sol    — PancakeSwap V3 LP ops + token validation
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
    error InvalidStrategy(address strategy);
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

### 1b. `contracts/shared-vault/interfaces/ISharedConfigManager.sol`

Extended from `IPrivateConfigManager` — adds strategy whitelisting.

```solidity
interface ISharedConfigManager {
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    function isVaultPaused() external view returns (bool);
    function feeRecipient() external view returns (address);

    // Strategy whitelist (for LP operations via delegatecall)
    function isWhitelistedStrategy(address strategy) external view returns (bool);
    function setWhitelistStrategies(address[] calldata strategies, bool isWhitelisted) external;

    // Target whitelist (for swap aggregator calls)
    function isWhitelistedTarget(address target) external view returns (bool);
    function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external;

    // Caller whitelist (authorized callers besides owner/admin)
    function isWhitelistedCaller(address caller) external view returns (bool);
    function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external;

    function setVaultPaused(bool _isVaultPaused) external;
    function setFeeRecipient(address newFeeRecipient) external;
}
```

### 1c. `contracts/shared-vault/interfaces/ISharedStrategy.sol`

Common interface for all shared vault strategies. Strategies validate that pool tokens are among the vault's managed tokens.

```solidity
interface ISharedStrategy {
    error InvalidPoolTokens();

    /// @notice Execute an LP operation. Called via delegatecall from SharedVault.
    /// @dev Strategy MUST validate that pool tokens are vault tokens by calling
    ///      ISharedVault(address(this)).isVaultToken(token) for each pool token.
    ///      Since this runs via delegatecall, address(this) is the vault.
    /// @param data Encoded operation params (strategy-specific)
    function execute(bytes calldata data) external payable;
}
```

**Token validation pattern** (used inside each strategy):
```solidity
// Inside strategy, running via delegatecall — address(this) is the vault
function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
}
```

This works because:
- Strategy runs via delegatecall in vault's context
- `address(this)` is the vault address
- Calling `ISharedVault(address(this)).isVaultToken()` is a regular CALL back to the vault's own code
- `isVaultToken()` is a view function — no reentrancy issues

### 1d. `contracts/shared-vault/interfaces/ISharedVault.sol`

```solidity
interface ISharedVault is ISharedCommon {
    event VaultDeposit(address indexed vaultFactory, address indexed account, uint256[4] amounts, uint256 shares);
    event VaultWithdraw(address indexed vaultFactory, address indexed account, uint256[4] amounts, uint256 shares);
    event VaultExecute(address indexed vaultFactory, address indexed strategy, bytes data);
    event VaultSwap(address indexed vaultFactory, address indexed swapTarget, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event SetVaultAdmin(address indexed vaultFactory, address indexed account, bool indexed isAdmin);
    event SetVaultOperator(address indexed vaultFactory, address indexed account, bool indexed isOperator);
    event VaultOwnerChanged(address indexed vaultFactory, address indexed previousOwner, address indexed newOwner);

    // --- Initialization ---
    function initialize(
        string calldata name,
        string calldata symbol,
        address[4] calldata _tokens,
        uint256[4] calldata initialAmounts,
        address _owner,
        address _configManager
    ) external;

    // --- Deposit / Withdraw (anyone) ---
    function deposit(uint256[4] calldata amounts, uint256 minShares) external returns (uint256 shares);
    function withdraw(uint256 shares, uint256[4] calldata minAmounts) external returns (uint256[4] memory amounts);

    // --- LP Operations (onlyAuthorized) ---
    /// @notice Execute LP operation via whitelisted strategy (delegatecall)
    /// @dev Strategy validates pool tokens are among vault's 4 tokens
    function execute(address strategy, bytes calldata data) external payable;

    /// @notice Swap between vault tokens via whitelisted aggregator target
    function swap(
        address swapTarget,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata swapData
    ) external;

    // --- Views ---
    function getTokens() external view returns (address[4] memory);
    function getIdleBalances() external view returns (uint256[4] memory);
    function previewDeposit(uint256[4] calldata amounts) external view returns (uint256 shares);
    function previewWithdraw(uint256 shares) external view returns (uint256[4] memory amounts);
    function isVaultToken(address token) external view returns (bool);
    function vaultOwner() external view returns (address);
    function tokenCount() external view returns (uint8);

    // --- Roles (onlyOwner) ---
    function grantAdminRole(address _address) external;
    function revokeAdminRole(address _address) external;
    function setOperator(address _operator) external;
    function transferOwnership(address newOwner) external;

    // --- Operator (onlyOperator) ---
    /// @notice Sweep non-vault ERC20 tokens (safeguard for stuck tokens)
    function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to) external;
    function sweepNativeToken(uint256 amount, address to) external;
    function sweepERC721(address token, uint256 tokenId, address to) external;
    function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external;
}
```

### 1e. `contracts/shared-vault/interfaces/ISharedVaultFactory.sol`

```solidity
interface ISharedVaultFactory is ISharedCommon {
    event VaultCreated(address indexed owner, address indexed vault, string name);
    event ConfigManagerSet(address configManager);
    event VaultImplementationSet(address vaultImplementation);

    function createVault(
        string calldata name,
        string calldata symbol,
        address[4] calldata tokens,
        uint256[4] calldata initialAmounts
    ) external returns (address vault);

    function createVault(
        string calldata name,
        string calldata symbol,
        address[4] calldata tokens,
        uint256[4] calldata initialAmounts,
        address strategy,
        bytes calldata strategyData
    ) external payable returns (address vault);

    function isVault(address vault) external view returns (bool);
}
```

---

## Step 2: SharedConfigManager

### `contracts/shared-vault/core/SharedConfigManager.sol`

**Based on**: `contracts/private-vault/core/PrivateConfigManager.sol` (78 lines)
**Changes**: Add strategy whitelisting alongside existing target/caller whitelisting.

```solidity
// Key storage additions vs PrivateConfigManager:
mapping(address => bool) public whitelistedStrategies;  // LP strategies (delegatecall)
// Existing from PrivateConfigManager:
mapping(address => bool) public whitelistedTargets;     // Swap aggregator targets (call)
mapping(address => bool) public whitelistedCallers;     // Authorized callers
bool public isVaultPaused;
address public feeRecipient;
```

---

## Step 3: SharedVault

### `contracts/shared-vault/core/SharedVault.sol`

**Inherits**: `ERC20PermitUpgradeable`, `ReentrancyGuardUpgradeable`, `ERC721Holder`, `ERC1155Holder`, `IERC1271`, `ISharedVault`

**Imports to reuse**:
- `FullMath` from `@uniswap/v3-core` (share math)
- `SafeERC20` from OpenZeppelin
- `SafeApprovalLib` from `contracts/private-vault/libraries/SafeApprovalLib.sol` (USDT approve(0))
- `SignatureChecker` from OpenZeppelin (for IERC1271)

### Storage Layout

```solidity
uint256 public constant SHARES_PRECISION = 1e18;

ISharedConfigManager public configManager;
address public override vaultOwner;
address public vaultFactory;
address public operator;                     // NEW: operator role for sweep

uint8 public override tokenCount;            // 2-4 active tokens
address[4] public tokens;                    // Fixed slots, address(0) = unused
mapping(address => bool) public isVaultToken;
mapping(address => bool) public admins;
```

### Roles

| Role | Who | Can Do |
|------|-----|--------|
| **Owner** | Vault creator | execute, swap, manage admins/operator, transfer ownership |
| **Admin** | Granted by owner | execute, swap |
| **Operator** | Set by owner | sweep non-vault tokens, sweep native, sweep ERC721/ERC1155 |
| **Depositor** | Anyone | deposit, withdraw (based on shares held) |
| **Whitelisted caller** | Via ConfigManager | execute, swap |

### Modifiers

```solidity
modifier onlyOwner()       — msg.sender == vaultOwner
modifier onlyAuthorized()  — vaultOwner OR admins OR configManager.isWhitelistedCaller
modifier onlyOperator()    — msg.sender == operator
modifier whenNotPaused()   — !configManager.isVaultPaused()
```

### Share Math — No Oracle, Proportional Ratio

**Shares represent `shares / totalSupply` fraction of every idle token balance.**

Idle balance = `IERC20(token).balanceOf(address(this))` — tokens locked in LP positions are NOT counted. This is intentional: the owner decides when to deploy/unwind LP. Depositors see only idle tokens via `previewWithdraw`.

**First deposit** (`totalSupply == 0`):
```
shares = amounts[refIndex] * SHARES_PRECISION
// refIndex = first token with amounts[i] > 0
// All nonzero amounts set the initial ratio
```

**Subsequent deposits** (`totalSupply > 0`):
```
For the reference token (first with idleBalance > 0 AND amounts > 0):
    shares = FullMath.mulDiv(amounts[refIndex], totalSupply, idleBalance[refIndex])

For each other active token with idleBalance > 0:
    expectedAmount = FullMath.mulDiv(shares, idleBalance[i], totalSupply)
    require(amounts[i] >= expectedAmount)
    // Only transfer expectedAmount to avoid excess

For tokens with idleBalance == 0:
    require(amounts[i] == 0)
```

**Withdrawal**:
```
currentTotalSupply = totalSupply()   // capture BEFORE burn
_burn(msg.sender, shares)
For each active token i:
    amounts[i] = FullMath.mulDiv(shares, idleBalance[i], currentTotalSupply)
    transfer amounts[i] to msg.sender
```

### Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `initialize(...)` | Factory only (initializer) | Set tokens, owner, configManager, mint initial shares |
| `deposit(uint256[4], uint256)` | Anyone (whenNotPaused) | Proportional multi-token deposit, mint shares |
| `withdraw(uint256, uint256[4])` | Share holders (nonReentrant) | Burn shares, return proportional idle tokens |
| `execute(address, bytes)` | onlyAuthorized + whenNotPaused | Delegatecall to whitelisted strategy |
| `swap(...)` | onlyAuthorized + whenNotPaused | Swap between vault tokens via whitelisted aggregator |
| `sweepTokens(...)` | onlyOperator | Sweep non-vault ERC20s only |
| `sweepNativeToken(...)` | onlyOperator | Sweep ETH |
| `sweepERC721(...)` | onlyOperator | Sweep ERC721 |
| `sweepERC1155(...)` | onlyOperator | Sweep ERC1155 |
| `grantAdminRole(address)` | onlyOwner | Grant admin |
| `revokeAdminRole(address)` | onlyOwner | Revoke admin |
| `setOperator(address)` | onlyOwner | Set operator address |
| `transferOwnership(address)` | onlyOwner | Transfer vault ownership |
| `getTokens()` | view | Return token addresses |
| `getIdleBalances()` | view | Return `balanceOf(this)` for each token |
| `previewDeposit(uint256[4])` | view | Preview shares for given amounts |
| `previewWithdraw(uint256)` | view | Preview token amounts for given shares |
| `isVaultToken(address)` | view | Check if address is a managed token |
| `isValidSignature(bytes32, bytes)` | view | EIP-1271 via vault owner |
| `decimals()` | view | Returns 18 |

### Execute Flow (LP Operations)

```
function execute(address strategy, bytes calldata data) external payable onlyAuthorized whenNotPaused nonReentrant {
    1. require(configManager.isWhitelistedStrategy(strategy), InvalidStrategy)
    2. (bool success, bytes memory result) = strategy.delegatecall(
           abi.encodeCall(ISharedStrategy.execute, (data))
       )
    3. if (!success) revert with original error
    4. emit VaultExecute(vaultFactory, strategy, data)
}
```

The strategy itself validates pool tokens via `ISharedVault(address(this)).isVaultToken(token)`.

### Swap Flow (Token Swaps via Aggregator)

```
function swap(
    address swapTarget, address tokenIn, address tokenOut,
    uint256 amountIn, uint256 minAmountOut, bytes calldata swapData
) external onlyAuthorized whenNotPaused nonReentrant {
    1. require(isVaultToken[tokenIn], TokenNotConfigured)
    2. require(isVaultToken[tokenOut], TokenNotConfigured)
    3. require(configManager.isWhitelistedTarget(swapTarget), InvalidTarget)
    4. uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this))
    5. IERC20(tokenIn).safeResetAndApprove(swapTarget, amountIn)
    6. (bool success, ) = swapTarget.call(swapData)
    7. require(success, SwapFailed)
    8. uint256 amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore
    9. require(amountOut >= minAmountOut, InsufficientOutput)
   10. emit VaultSwap(vaultFactory, swapTarget, tokenIn, tokenOut, amountIn, amountOut)
}
```

### Sweep (Operator Only)

```solidity
function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to) external onlyOperator {
    for (uint i = 0; i < _tokens.length; i++) {
        require(!isVaultToken[_tokens[i]], CannotSweepVaultToken());
        IERC20(_tokens[i]).safeTransfer(to, amounts[i]);
    }
}

function sweepNativeToken(uint256 amount, address to) external onlyOperator { ... }
function sweepERC721(address token, uint256 tokenId, address to) external onlyOperator { ... }
function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external onlyOperator { ... }
```

### Deposit Flow

```
1. For each active token i (tokens[i] != address(0)):
   a. Read idleBalance[i] = IERC20(tokens[i]).balanceOf(address(this))
2. If totalSupply == 0:
   a. Find refIndex (first i with amounts[i] > 0)
   b. shares = amounts[refIndex] * SHARES_PRECISION
   c. For each active token: if amounts[i] > 0, transferFrom(sender, vault, amounts[i])
3. If totalSupply > 0:
   a. Find refIndex (first i with idleBalance[i] > 0 AND amounts[i] > 0)
   b. shares = FullMath.mulDiv(amounts[refIndex], totalSupply, idleBalance[refIndex])
   c. For each other active token with idleBalance[i] > 0:
      - expectedAmount = FullMath.mulDiv(shares, idleBalance[i], totalSupply)
      - require(amounts[i] >= expectedAmount, InvalidRatio())
      - Transfer expectedAmount (not full amounts[i]) to avoid excess
   d. For tokens with idleBalance == 0: require(amounts[i] == 0)
4. require(shares >= minShares)
5. _mint(msg.sender, shares)
```

### Withdraw Flow

```
1. require(shares > 0 && shares <= balanceOf(msg.sender))
2. currentTotalSupply = totalSupply()
3. _burn(msg.sender, shares)
4. For each active token i:
   a. idleBalance = IERC20(tokens[i]).balanceOf(address(this))
   b. amounts[i] = FullMath.mulDiv(shares, idleBalance, currentTotalSupply)
   c. require(amounts[i] >= minAmounts[i])
   d. if amounts[i] > 0: safeTransfer(msg.sender, amounts[i])
5. return amounts
```

---

## Step 4: Strategies

Each strategy wraps an existing external protocol (V3Utils, V4Utils, etc.) and adds **token validation** — ensuring LP pool tokens are among the vault's 4 managed tokens.

### Strategy Pattern (all strategies follow this)

```solidity
contract SharedXxxStrategy is ISharedStrategy {
    address public immutable externalProtocol;  // V3Utils, V4UtilsRouter, etc.

    function execute(bytes calldata data) external payable override {
        // 1. Decode operation type + params from data
        // 2. Extract pool token0/token1 from params
        // 3. Validate: ISharedVault(address(this)).isVaultToken(token0)
        // 4. Validate: ISharedVault(address(this)).isVaultToken(token1)
        // 5. Execute LP operation via externalProtocol
    }

    function _validateVaultToken(address token) internal view {
        require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
    }
}
```

### 4a. `contracts/shared-vault/strategies/SharedV3Strategy.sol`

Wraps `V3Utils` (same external contract used by private vault's V3UtilsStrategy).

```solidity
contract SharedV3Strategy is ISharedStrategy {
    using SafeApprovalLib for IERC20;

    address public immutable v3utils;
    ISharedConfigManager public immutable configManager;

    enum OperationType { SWAP_AND_MINT, SWAP_AND_INCREASE, SAFE_TRANSFER_NFT }

    function execute(bytes calldata data) external payable override {
        OperationType opType = abi.decode(data[:32], (OperationType));

        if (opType == OperationType.SWAP_AND_MINT) {
            _swapAndMint(data[32:]);
        } else if (opType == OperationType.SWAP_AND_INCREASE) {
            _swapAndIncreaseLiquidity(data[32:]);
        } else if (opType == OperationType.SAFE_TRANSFER_NFT) {
            _safeTransferNft(data[32:]);
        }
    }

    function _swapAndMint(bytes calldata data) internal {
        (IV3Utils.SwapAndMintParams memory params, address[] memory approveTokens, uint256[] memory approveAmounts, uint256 ethValue) = abi.decode(...);
        // Validate pool tokens
        _validateVaultToken(params.token0);
        _validateVaultToken(params.token1);
        // Approve + call V3Utils
        _approveTokens(approveTokens, approveAmounts, v3utils);
        params.recipient = address(this);
        IV3Utils(v3utils).swapAndMint{value: ethValue}(params);
    }

    function _swapAndIncreaseLiquidity(bytes calldata data) internal {
        // Similar: decode, validate tokens from NFPM position, approve, call V3Utils
    }

    function _safeTransferNft(bytes calldata data) internal {
        // Decode NFPM address, tokenId, instructions
        // Get token0/token1 from NFPM.positions(tokenId) and validate
        // Transfer NFT to V3Utils with instructions (CHANGE_RANGE, WITHDRAW, COMPOUND)
    }
}
```

**Reference**: `contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol` (89 lines)
**Reference**: `contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol` (IV3Utils structs)

Key difference from V3UtilsStrategy: adds token validation, no skim surplus (keep in vault).

### 4b. `contracts/shared-vault/strategies/SharedV4Strategy.sol`

Wraps `V4UtilsRouter` (same external contract used by private vault's V4UtilsStrategy).

```solidity
contract SharedV4Strategy is ISharedStrategy {
    address public immutable v4UtilsRouter;

    function execute(bytes calldata data) external payable override {
        // Decode: posm, tokenId, params, ethValue, approveTokens, approveAmounts
        // Validate pool tokens (extract from POSM position data)
        // Approve + call V4UtilsRouter.execute(posm, params)
    }
}
```

**Reference**: `contracts/private-vault/strategies/lpv4/V4UtilsStrategy.sol` (64 lines)

### 4c. `contracts/shared-vault/strategies/SharedAerodromeStrategy.sol`

Handles Aerodrome CL positions. Wraps the same V3Utils contract but with Aerodrome-specific NFPM and pool factories.

```solidity
contract SharedAerodromeStrategy is ISharedStrategy {
    address public immutable v3utils;    // V3Utils supports Aerodrome protocol flag
    address public immutable gaugeFactory;

    function execute(bytes calldata data) external payable override {
        // Operations: SWAP_AND_MINT, SWAP_AND_INCREASE, SAFE_TRANSFER_NFT,
        //             DEPOSIT_GAUGE, WITHDRAW_GAUGE, HARVEST_GAUGE
        // Token validation on all LP operations
        // Gauge operations for farming rewards
    }
}
```

**Reference**: `contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol` (128 lines)
**Note**: V3Utils already supports Aerodrome via the `protocol` field in SwapAndMintParams.

### 4d. `contracts/shared-vault/strategies/SharedPancakeV3Strategy.sol`

Handles PancakeSwap V3 positions + MasterChef farming.

```solidity
contract SharedPancakeV3Strategy is ISharedStrategy {
    address public immutable v3utils;
    address public immutable masterChef;

    function execute(bytes calldata data) external payable override {
        // LP operations via V3Utils (protocol=PancakeSwap)
        // Farming: deposit/withdraw/harvest MasterChef
        // Token validation on all LP operations
    }
}
```

**Reference**: `contracts/private-vault/strategies/farm/PancakeV3FarmingStrategy.sol` (100 lines)

---

## Step 5: SharedVaultFactory

### `contracts/shared-vault/core/SharedVaultFactory.sol`

**Based on**: `contracts/private-vault/core/PrivateVaultFactory.sol` (128 lines)

**Inherits**: `OwnableUpgradeable`, `PausableUpgradeable`, `Withdrawable`, `ISharedVaultFactory`

### Key differences from PrivateVaultFactory:

1. **Salt**: `keccak256(abi.encodePacked(name, symbol, msg.sender, "shared-1.0"))`
2. **createVault (simple)**: Transfers up to 4 initial token amounts to vault before `initialize`
3. **createVault (with strategy)**: Same as simple + executes strategy for initial LP setup
4. **initialize call**: Passes `name, symbol, tokens[4], initialAmounts[4], msg.sender, configManager`

### Create Flow

```
1. Clone vault implementation deterministically
2. For each token i with initialAmounts[i] > 0:
   IERC20(tokens[i]).safeTransferFrom(msg.sender, vault, initialAmounts[i])
3. ISharedVault(vault).initialize(name, symbol, tokens, initialAmounts, msg.sender, configManager)
4. Register vault in vaultsByAddress and allVaults
5. (Optional) Execute strategy for initial LP setup
```

---

## Step 6: Deployment Scripts & Config

### 6a. Extend `configs/interfaces.ts`

Add `IConfigShared` interface:
```typescript
export interface IConfigShared {
    sharedVault?: { enabled?: boolean; autoVerifyContract?: boolean; };
    sharedVaultFactory?: { enabled?: boolean; autoVerifyContract?: boolean; };
    sharedConfigManager?: { enabled?: boolean; autoVerifyContract?: boolean; };
    sharedV3Strategy?: { enabled?: boolean; autoVerifyContract?: boolean; };
    sharedV4Strategy?: { enabled?: boolean; autoVerifyContract?: boolean; };
    sharedAerodromeStrategy?: { enabled?: boolean; autoVerifyContract?: boolean; };
    sharedPancakeV3Strategy?: { enabled?: boolean; autoVerifyContract?: boolean; };
}
```

Add `IConfigShared` to the `IConfig` extends clause.

### 6b. Create `scripts/deployLogic-shared.ts`

Deploy sequence:
1. Deploy SharedConfigManager (with initialize)
2. Deploy SharedVault implementation
3. Deploy SharedVaultFactory (with initialize → configManager + implementation)
4. Deploy SharedV3Strategy (constructor: v3utils address)
5. Deploy SharedV4Strategy (constructor: v4UtilsRouter address)
6. Deploy SharedAerodromeStrategy (constructor: v3utils, gaugeFactory)
7. Deploy SharedPancakeV3Strategy (constructor: v3utils, masterChef)
8. Whitelist strategies in SharedConfigManager

### 6c. Create `scripts/deployer-shared.ts`

Entry point that calls deployLogic-shared functions.

---

## Step 7: Tests

### 7a. Unit Tests — `test/unit/SharedVault.t.sol` (Foundry)

Test cases:
- **Initialization**: Token setup, owner, configManager, initial share mint
- **Deposit (first)**: Sets ratio, mints shares at SHARES_PRECISION
- **Deposit (subsequent)**: Validates ratio, mints proportional shares
- **Deposit (ratio mismatch)**: Reverts with InvalidRatio
- **Withdraw**: Burns shares, returns proportional tokens
- **Withdraw (partial)**: Correct proportional amounts
- **Withdraw (all)**: Full withdrawal clears balances
- **Execute**: Delegatecall to whitelisted strategy succeeds
- **Execute (unauthorized)**: Non-authorized caller reverts
- **Execute (non-whitelisted strategy)**: Reverts with InvalidStrategy
- **Swap**: Swap between vault tokens via whitelisted target
- **Swap (non-vault token)**: Reverts with TokenNotConfigured
- **Swap (non-whitelisted target)**: Reverts with InvalidTarget
- **Sweep (operator)**: Non-vault tokens sweep OK
- **Sweep (vault tokens)**: Reverts with CannotSweepVaultToken
- **Sweep (non-operator)**: Reverts with Unauthorized
- **Roles**: Grant/revoke admin, set operator, transfer ownership
- **Pause**: All operations blocked when paused
- **Preview functions**: Correct previews
- **Edge cases**: Zero idle balance tokens, 2-token vault, 3-token vault

### 7b. Integration Tests — `test/integration/Integration.SharedVault.t.sol`

- Fork test with real Uniswap V3/V4 positions
- Full lifecycle: deposit → execute strategy to mint LP → swap → withdraw
- Multi-DEX: create positions on different DEXes in same vault
- Strategy token validation: reject LP operations with non-vault tokens

---

## Reuse Summary

| Component | Source | How Used |
|-----------|--------|----------|
| ConfigManager pattern | `PrivateConfigManager.sol` | Adapt with strategy whitelist addition |
| Factory pattern | `PrivateVaultFactory.sol` | Adapt for multi-token initial deposit + strategy exec |
| `FullMath` | `@uniswap/v3-core` | Share math (mulDiv) |
| `SafeERC20` | OpenZeppelin | Token transfers |
| `SafeApprovalLib` | `contracts/private-vault/libraries/SafeApprovalLib.sol` | USDT approve(0) in strategies & swap |
| `CollectFee` | `contracts/private-vault/libraries/CollectFee.sol` | Fee collection in strategies |
| `ERC20PermitUpgradeable` | OpenZeppelin | Share token with EIP-2612 |
| `Clones` | OpenZeppelin | Deterministic proxy deployment |
| `Withdrawable` | `contracts/common/Withdrawable.sol` | Factory sweep functions |
| `SignatureChecker` | OpenZeppelin | IERC1271 support |
| `IV3Utils` structs | `contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol` | Reuse SwapAndMintParams, Instructions, etc. |
| `IV4UtilsRouter` | `contracts/private-vault/interfaces/strategies/lpv4/IV4UtilsRouter.sol` | Reuse V4 execution interface |
| V3UtilsStrategy pattern | `contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol` | Adapt with token validation, no skim |
| V4UtilsStrategy pattern | `contracts/private-vault/strategies/lpv4/V4UtilsStrategy.sol` | Adapt with token validation, no skim |
| AerodromeFarming pattern | `contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol` | Adapt with token validation |
| PancakeV3Farming pattern | `contracts/private-vault/strategies/farm/PancakeV3FarmingStrategy.sol` | Adapt with token validation |
| Admin management | `PrivateVault.sol:241-254` | Same grant/revoke pattern |

---

## Implementation Order

1. **Interfaces** (ISharedCommon → ISharedConfigManager → ISharedStrategy → ISharedVault → ISharedVaultFactory)
2. **SharedConfigManager** (adapt from PrivateConfigManager + strategy whitelist)
3. **SharedVault** (largest — ERC20 shares + execute + swap + deposit/withdraw + operator)
4. **SharedVaultFactory** (adapted from PrivateVaultFactory)
5. **SharedV3Strategy** (Uniswap V3 LP with token validation)
6. **SharedV4Strategy** (Uniswap V4 LP with token validation)
7. **SharedAerodromeStrategy** (Aerodrome LP + farming with token validation)
8. **SharedPancakeV3Strategy** (PancakeSwap V3 LP + farming with token validation)
9. **Deployment scripts** (deployLogic-shared.ts, deployer-shared.ts, config extension)
10. **Tests** (unit + integration)
11. **Compile & verify** (`npx hardhat compile`)

---

## Verification

1. `npx hardhat compile` — all contracts compile without errors
2. `forge test --match-contract SharedVault` — unit tests pass
3. `forge test --match-contract IntegrationSharedVault` — integration tests pass (requires fork RPC)
4. Manual review: strategy token validation, share math edge cases, operator restrictions
