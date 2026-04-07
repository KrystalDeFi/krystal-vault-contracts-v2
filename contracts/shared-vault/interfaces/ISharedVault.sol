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
  event VaultOwnerFeeBasisPointUpdated(address indexed vaultFactory, uint16 basisPoints);

  /// @dev Tracked LP position
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
  function initialize(
    string calldata name,
    address[4] calldata _tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    address _operator,
    address _configManager,
    address _weth
  ) external;

  // --- Deposit / Withdraw ---

  /// @notice Deposit tokens and receive shares. Send ETH via msg.value to auto-wrap to WETH
  ///         (msg.value must match amounts[wethIndex] exactly; only the proportional amount
  ///          is wrapped — excess ETH is refunded directly without an unwrap round-trip).
  function deposit(uint256[4] calldata amounts, uint256 minShares) external payable returns (uint256 shares);

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

  function previewWithdraw(uint256 shares) external view returns (uint256[4] memory amounts);

  function isVaultToken(address token) external view returns (bool);

  function vaultOwner() external view returns (address);

  function configManager() external view returns (ISharedConfigManager);

  function weth() external view returns (address);

  function tokenCount() external view returns (uint16);

  // --- Roles (onlyOwner) ---
  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function setOperator(address _operator) external;

  function setPaused(bool _paused) external;

  /// @notice Basis points of LP performance/collection fees routed to `vaultOwner` on proportional exits (max 10_000).
  function vaultOwnerFeeBasisPoint() external view returns (uint16);

  function setVaultOwnerFeeBasisPoint(uint16 basisPoints) external;

  function transferOwnership(address newOwner) external;

  // --- Operator (onlyOperator) ---
  function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to) external;

  function sweepNativeToken(uint256 amount, address to) external;

  function sweepERC721(address token, uint256 tokenId, address to) external;

  function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external;
}
