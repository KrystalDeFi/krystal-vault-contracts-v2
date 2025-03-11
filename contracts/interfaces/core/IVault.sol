// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../strategies/IStrategy.sol";

interface IVault is ICommon {
  event Deposit(address indexed account, uint256 shares);

  event Allocate(Asset[] inputAssets, IStrategy strategy, Asset[] newAssets);

  event Deallocate(Asset[] inputAssets, Asset[] returnedAssets);

  event SweepToken(address[] tokens);

  event SweepNFToken(address[] tokens, uint256[] tokenIds);

  error InvalidAssetAmount();
  error InvalidSweepAsset();
  error InvalidAssetStrategy();
  error InvalidAssetTokenId();
  error InvalidAssetType();

  function vaultOwner() external view returns (address);

  function initialize(
    VaultCreateParams memory params,
    address _owner,
    address _whitelistManager,
    address _vaultAutomator
  ) external;

  function deposit(uint256 amount) external returns (uint256 shares);

  function allocate(Asset[] memory inputAssets, IStrategy strategy, bytes calldata data) external;

  function deallocate(address token, uint256 tokenId, uint256 amount, bytes calldata data) external;

  function getTotalValue() external returns (uint256);

  function getAssetAllocations() external returns (Asset[] memory assets, uint256[] memory values);

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function sweepToken(address[] memory tokens) external;

  function sweepNFTToken(address[] memory tokens, uint256[] memory tokenIds) external;
}
