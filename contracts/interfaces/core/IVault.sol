// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../strategies/IStrategy.sol";

interface IVault is ICommon {
  event Deposit(address indexed account, uint256 shares);

  event Withdraw(address indexed account, uint256 shares);

  event Allocate(AssetLib.Asset[] inputAssets, IStrategy strategy, AssetLib.Asset[] newAssets);

  event Deallocate(AssetLib.Asset[] inputAssets, AssetLib.Asset[] returnedAssets);

  event SweepToken(address[] tokens);

  event SweepERC721(address[] _tokens, uint256[] _tokenIds);

  event SweepERC1155(address[] _tokens, uint256[] _tokenIds, uint256[] _amounts);

  event SetVaultConfig(VaultConfig config);

  error InvalidAssetToken();
  error InvalidAssetAmount();
  error InvalidSweepAsset();
  error InvalidAssetStrategy();
  error InvalidAssetTokenId();
  error InvalidAssetType();
  error DepositNotAllowed();
  error MaxPositionsReached();
  error InvalidShares();
  error Unauthorized();
  error InsufficientShares();

  function vaultOwner() external view returns (address);

  function initialize(VaultCreateParams memory params, address _owner, address _configManager) external;

  function deposit(uint256 principalAmount, uint256 minShares) external returns (uint256 returnShares);

  function withdraw(uint256 shares) external;

  function allocate(AssetLib.Asset[] memory inputAssets, IStrategy strategy, bytes calldata data) external;

  function deallocate(address token, uint256 tokenId, uint256 amount, bytes calldata data) external;

  function getTotalValue() external returns (uint256);

  function getAssetAllocations() external returns (AssetLib.Asset[] memory assets);

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function sweepToken(address[] memory tokens) external;

  function sweepERC721(address[] memory _tokens, uint256[] memory _tokenIds) external;

  function sweepERC1155(address[] memory _tokens, uint256[] memory _tokenIds, uint256[] memory _amounts) external;

  function allowDeposit(VaultConfig memory _config) external;

  function getInventory() external view returns (AssetLib.Asset[] memory assets);

  function getVaultConfig()
    external
    view
    returns (
      bool allowDeposit,
      uint8 rangeStrategyType,
      uint8 tvlStrategyType,
      address principalToken,
      address[] memory supportedAddresses
    );
}
