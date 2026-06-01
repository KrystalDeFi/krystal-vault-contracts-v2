// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";
import "./ISharedConfigManager.sol";

interface ISharedVault is ISharedCommon {
  event VaultDeposit(address indexed vaultFactory, address indexed account, uint256[4] amounts, uint256 shares);
  event VaultWithdraw(address indexed vaultFactory, address indexed account, uint256[4] amounts, uint256 shares);
  event VaultExecute(address indexed vaultFactory, address indexed target, bytes data);
  event SetVaultAdmin(address indexed vaultFactory, address indexed account, bool indexed isAdmin);
  event SetVaultOperator(address indexed vaultFactory, address indexed previousOperator, address indexed newOperator);
  event VaultOwnerChanged(address indexed vaultFactory, address indexed previousOwner, address indexed newOwner);
  event VaultPausedUpdated(address indexed vaultFactory, bool paused);
  /// @notice Emitted exactly once at vault initialization.
  /// @dev `vaultOwnerFeeBasisPoint` is locked at initialization and cannot be changed afterward.
  event VaultOwnerFeeBasisPointSet(address indexed vaultFactory, uint16 basisPoints);
  /// @notice Emitted when the vault owner forcibly drops a position from tracking.
  ///         The NFT is transferred to the operator (if set) so liquidity can be recovered later;
  ///         if no operator is set the NFT remains in the vault.
  event PositionDropped(address indexed vaultFactory, address indexed nfpm, uint256 indexed tokenId);
  /// @notice Emitted when the operator recovers a previously dropped position back into tracking.
  event PositionRecovered(address indexed vaultFactory, address indexed nfpm, uint256 indexed tokenId);

  /// @dev Tracked LP position
  ///      Vault token slots are ERC20 addresses; `address(0)` means an unused slot. Native-currency
  ///      V4/Pancake pools that use `address(0)` as a currency are unsupported. Use wrapped-native
  ///      ERC20 pools instead.
  struct Position {
    address strategy; // Strategy contract (used for getPositionAmounts valuation)
    address nfpm; // NFT Position Manager
    uint256 tokenId; // Position NFT ID
    address token0; // Pool token0
    address token1; // Pool token1
  }

  /// @dev A single unit of work passed to execute(). See ISharedCommon.CallType for full semantics.
  struct Action {
    address target;
    bytes data;
    CallType callType;
  }

  // --- Initialization ---
  /// @param _vaultOwnerFeeBasisPoint Basis points of LP performance/collection fees routed to `_owner`
  ///        on proportional exits (max 10_000). **Locked at initialization** — there is no setter.
  function initialize(
    string calldata name,
    address[4] calldata _tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    address _operator,
    address _configManager,
    address _weth,
    uint16 _vaultOwnerFeeBasisPoint
  ) external;

  // --- Deposit / Withdraw ---

  /// @notice Deposit tokens and receive shares. Send ETH via msg.value to auto-wrap to WETH
  ///         (msg.value must match amounts[wethIndex] exactly; only the proportional amount
  ///          is wrapped — excess ETH is refunded directly without an unwrap round-trip).
  /// @param slippageBps Slippage tolerance in basis points (e.g. 100 = 1%) applied to each LP
  ///        position's proportional deposit: amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000).
  ///        Must be ≤ 10000. Pass 0 to skip the amountMin floor.
  function deposit(uint256[4] calldata amounts, uint16 slippageBps) external payable returns (uint256 shares);

  /// @notice Deposit tokens from the caller and mint shares to `receiver`.
  /// @dev Preserves gateway/account attribution while the caller supplies the tokens.
  function deposit(
    uint256[4] calldata amounts,
    uint16 slippageBps,
    address receiver
  ) external payable returns (uint256 shares);

  /// @notice Burn shares and withdraw proportional tokens.
  ///         If the vault has active LP positions, each strategy exits its proportional share
  ///         of liquidity first; idle tokens are then withdrawn.
  /// @param shares Number of vault shares to burn.
  /// @param minAmounts Per-token minimum output (aggregate slippage guard).
  ///        Individual LP exits use zero slippage bounds so one tight position cannot
  ///        revert the whole withdrawal. Instead, any sandwich-induced shortfall reduces
  ///        the aggregate `amounts[i]` and is caught here. Derive values from
  ///        `previewWithdraw()` minus acceptable slippage.
  /// @param unwrap If true, any WETH amount is unwrapped to native ETH before sending.
  function withdraw(
    uint256 shares,
    uint256[4] calldata minAmounts,
    bool unwrap
  ) external returns (uint256[4] memory amounts);

  /// @notice Burn `account` shares and withdraw proportional tokens to the caller.
  /// @dev If caller is not `account`, the caller must have sufficient share allowance.
  ///      `account` only selects whose shares are burned; proceeds are sent to `msg.sender`, not
  ///      to `account`.
  function withdraw(
    uint256 shares,
    uint256[4] calldata minAmounts,
    bool unwrap,
    address account
  ) external returns (uint256[4] memory amounts);

  // --- Execute (LP operations + swaps, onlyAuthorized) ---

  /// @notice Execute one or more actions: strategy delegatecalls (LP) and/or direct swap calls.
  ///         For strategy actions the vault tracks LP position changes.
  ///         For swap actions the vault validates tokenIn/tokenOut are vault tokens and checks
  ///         that the output meets minAmountOut.
  function execute(Action[] calldata actions) external;

  // --- Views ---
  function getTokens() external view returns (address[4] memory);

  function getIdleBalances() external view returns (uint256[4] memory);

  function getTotalBalances() external view returns (uint256[4] memory);

  function getPositionCount() external view returns (uint256);

  function getPosition(
    uint256 index
  ) external view returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1);

  function previewDeposit(uint256[4] calldata amounts) external view returns (uint256 shares);

  /// @notice Preview token amounts returned for burning `shares`, NET of LP exit fees.
  /// @dev Returns the proportional share of (idle + LP principal + (1 − feeRate) × uncollected LP fees).
  ///      The fee deduction uses the same clamp logic as `SharedStrategyFeeConfig.performanceFeeConfig`:
  ///      `platformFeeBasisPoint` + `vaultOwnerFeeBasisPoint`, with the owner share silently clamped if
  ///      the sum exceeds 10000. Principal exits incur no perf/platform fee.
  ///      Callers should still apply an AMM-slippage margin when deriving `minAmounts` for `withdraw()`.
  function previewWithdraw(uint256 shares) external view returns (uint256[4] memory amounts);

  /// @notice Per-token minimum amounts required for a subsequent deposit.
  /// @dev Returns zeros on first deposit (totalSupply == 0) because no proportional floor applies.
  ///      For subsequent deposits each non-zero-balance slot returns
  ///      `10 ** max(0, token.decimals() - configManager.minTokenPrecision())`.
  ///      Slots whose total balance is zero must be deposited at exactly zero; their entry is 0.
  function getMinDepositAmounts() external view returns (uint256[4] memory minAmounts);

  function isVaultToken(address token) external view returns (bool);

  function vaultOwner() external view returns (address);

  function configManager() external view returns (ISharedConfigManager);

  function weth() external view returns (address);

  function tokenCount() external view returns (uint16);

  // --- Position management (onlyOwner) ---

  /// @notice Forcibly remove a position from vault tracking without exiting liquidity.
  /// @dev **Custody / trust:** When `operator` is non-zero, the position NFT is transferred from this vault
  ///      to `operator`. The vault owner initiates `dropPosition` but **cannot** unilaterally retrieve the
  ///      NFT on-chain afterward—only `recoverPosition`, callable by `operator` only, returns custody to the
  ///      vault. There is no alternative on-chain path for the vault owner if the operator is unavailable or
  ///      compromised (unlike the no-`operator` case: the NFT stays in the vault and may be recovered via
  ///      `sweepERC721`). Assume the operator is trusted for NFT custody between drop and recover.
  /// @param nfpm  NFT position manager that issued the position
  /// @param tokenId  The position token ID to drop
  function dropPosition(address nfpm, uint256 tokenId) external;

  /// @notice Recover a previously dropped position back into vault tracking.
  ///         Pulls the NFT from the operator (caller must have approved this vault as spender),
  ///         re-adds the position to tracking, and re-enables LP valuation and proportional exits.
  ///         The strategy must be whitelisted in ConfigManager (it is delegatecalled on deposits/withdrawals).
  /// @dev `token0` and `token1` must match the pool’s currencies; both must be tokens configured on this vault
  ///      (`isVaultToken`). Wrong addresses break LP valuation and proportional exits. The operator is trusted
  ///      to supply the correct pair (validated on-chain against the vault token set).
  /// @param nfpm      NFT position manager that issued the position
  /// @param tokenId   The position token ID to recover
  /// @param strategy  Whitelisted strategy to use for this position (must implement ISharedStrategy)
  /// @param token0    Pool token0 (must be a configured vault token)
  /// @param token1    Pool token1 (must be a configured vault token)
  function recoverPosition(address nfpm, uint256 tokenId, address strategy, address token0, address token1) external;

  // --- Roles (onlyOwner) ---
  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function setPaused(bool _paused) external;

  /// @notice Basis points of LP performance/collection fees routed to `vaultOwner` on proportional exits (max 10_000).
  /// @dev Set at initialization and immutable thereafter — there is no setter.
  function vaultOwnerFeeBasisPoint() external view returns (uint16);

  function transferOwnership(address newOwner) external;

  // --- Operator (onlyOperator) ---
  function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to) external;

  function sweepNativeToken(uint256 amount, address to) external;

  function sweepERC721(address token, uint256 tokenId, address to) external;

  function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external;
}
