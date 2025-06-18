// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../strategies/IStrategy.sol";

interface IVault is ICommon {
  event VaultDeposit(address indexed vaultFactory, address indexed account, uint256 principalAmount, uint256 shares);

  event VaultWithdraw(address indexed vaultFactory, address indexed account, uint256 principalAmount, uint256 shares);

  event VaultAllocate(
    address indexed vaultFactory, AssetLib.Asset[] inputAssets, IStrategy strategy, AssetLib.Asset[] newAssets
  );

  event VaultHarvest(address indexed vaultFactory, AssetLib.Asset[] harvestedAssets);

  event VaultHarvestPrivate(address indexed vaultFactory, address indexed owner, uint256 principalHarvestedAmount);

  event SweepToken(address[] tokens);

  event SweepERC721(address[] _tokens, uint256[] _tokenIds);

  event SweepERC1155(address[] _tokens, uint256[] _tokenIds);

  event SetVaultConfig(address indexed vaultFactory, VaultConfig config);

  error VaultPaused();
  error InvalidAssetToken();
  error InvalidAssetAmount();
  error InvalidSweepAsset();
  error InvalidAssetStrategy();
  error DepositAllowed();
  error DepositNotAllowed();
  error MaxPositionsReached();
  error InvalidShares();
  error Unauthorized();
  error InsufficientShares();
  error FailedToSendEther();
  error InvalidWETH();
  error InsufficientReturnAmount();
  error ExceedMaxAllocatePerBlock();

  function vaultOwner() external view returns (address);

  function WETH() external view returns (address);

  function initialize(
    VaultCreateParams calldata params,
    address _owner,
    address _operator,
    address _configManager,
    address _weth
  ) external;

  function deposit(uint256 principalAmount, uint256 minShares) external payable returns (uint256 returnShares);

  function depositPrincipal(uint256 principalAmount) external payable returns (uint256 shares);

  function withdraw(uint256 shares, bool unwrap, uint256 minReturnAmount) external returns (uint256 returnAmount);

  function withdrawPrincipal(uint256 amount, bool unwrap) external returns (uint256 returnAmount);

  function allocate(
    AssetLib.Asset[] calldata inputAssets,
    IStrategy strategy,
    uint64 gasFeeBasisPoint,
    bytes calldata data
  ) external;

  function harvest(AssetLib.Asset calldata asset, uint256 amountTokenOutMin)
    external
    returns (AssetLib.Asset[] memory harvestedAssets);

  function harvestPrivate(AssetLib.Asset[] calldata asset, bool unwrap, uint256 amountTokenOutMin) external;

  function getTotalValue() external view returns (uint256);

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function sweepToken(address[] calldata tokens) external;

  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds) external;

  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds) external;

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
