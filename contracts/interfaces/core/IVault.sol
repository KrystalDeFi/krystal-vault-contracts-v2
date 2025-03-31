// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../strategies/IStrategy.sol";

interface IVault is ICommon {
  event Deposit(address indexed account, uint256 principalAmount, uint256 shares);

  event Withdraw(address indexed account, uint256 principalAmount, uint256 shares);

  event Allocate(AssetLib.Asset[] inputAssets, IStrategy strategy, AssetLib.Asset[] newAssets);

  event Deallocate(AssetLib.Asset[] inputAssets, AssetLib.Asset[] returnedAssets);

  event Harvest(AssetLib.Asset[] harvestedAssets);

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
  error FailedToSendEther();
  error InvalidWETH();
  error InsufficientReturnAmount();

  function vaultOwner() external view returns (address);

  function WETH() external view returns (address);

  function initialize(VaultCreateParams calldata params, address _owner, address _configManager, address _weth)
    external;

  function deposit(uint256 principalAmount, uint256 minShares) external payable returns (uint256 returnShares);

  function withdraw(uint256 shares, bool unwrap, uint256 minReturnAmount) external;

  function allocate(
    AssetLib.Asset[] calldata inputAssets,
    IStrategy strategy,
    uint16 gasFeeBasisPoint,
    bytes calldata data
  ) external;

  function getTotalValue() external returns (uint256);

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function sweepToken(address[] calldata tokens) external;

  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds) external;

  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds, uint256[] calldata _amounts) external;

  function allowDeposit(VaultConfig calldata _config) external;

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
