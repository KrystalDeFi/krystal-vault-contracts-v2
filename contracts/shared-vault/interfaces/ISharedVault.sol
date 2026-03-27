// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";

interface ISharedVault is ISharedCommon {
  event VaultDeposit(address indexed vaultFactory, address indexed account, uint256[4] amounts, uint256 shares);
  event VaultWithdraw(address indexed vaultFactory, address indexed account, uint256[4] amounts, uint256 shares);
  event VaultExecute(address indexed vaultFactory, address indexed strategy, bytes data);
  event VaultSwap(
    address indexed vaultFactory,
    address indexed swapTarget,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );
  event SetVaultAdmin(address indexed vaultFactory, address indexed account, bool indexed isAdmin);
  event SetVaultOperator(address indexed vaultFactory, address indexed previousOperator, address indexed newOperator);
  event VaultOwnerChanged(address indexed vaultFactory, address indexed previousOwner, address indexed newOwner);
  event VaultPausedUpdated(address indexed vaultFactory, bool paused);

  // --- Initialization ---
  function initialize(
    string calldata name,
    string calldata symbol,
    address[4] calldata _tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    address _configManager
  ) external;

  // --- Deposit / Withdraw ---
  function deposit(uint256[4] calldata amounts, uint256 minShares) external returns (uint256 shares);

  function withdraw(uint256 shares, uint256[4] calldata minAmounts) external returns (uint256[4] memory amounts);

  // --- LP Operations (onlyAuthorized) ---
  function execute(address strategy, bytes calldata data) external payable;

  // --- Swap (onlyAuthorized) ---
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

  function getTotalBalances() external view returns (uint256[4] memory);

  function getPositionCount() external view returns (uint256);

  function previewDeposit(uint256[4] calldata amounts) external view returns (uint256 shares);

  function previewWithdraw(uint256 shares) external view returns (uint256[4] memory amounts);

  function isVaultToken(address token) external view returns (bool);

  function vaultOwner() external view returns (address);

  function tokenCount() external view returns (uint8);

  // --- Roles (onlyOwner) ---
  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function setOperator(address _operator) external;

  function setPaused(bool _paused) external;

  function transferOwnership(address newOwner) external;

  // --- Operator (onlyOperator) ---
  function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to) external;

  function sweepNativeToken(uint256 amount, address to) external;

  function sweepERC721(address token, uint256 tokenId, address to) external;

  function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external;
}
