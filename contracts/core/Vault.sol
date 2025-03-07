// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IStrategy.sol";
import "../interfaces/IVault.sol";

contract Vault is AccessControlUpgradeable, ERC20PermitUpgradeable, ReentrancyGuard, IVault {
  using SafeERC20 for IERC20;

  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");

  address public principalToken;

  mapping(address => mapping(uint256 => Asset)) public currentAssets;

  constructor() {}

  /// @notice Initializes the vault
  /// @param params Vault creation parameters
  /// @param _owner Owner of the vault
  /// @param _vaultAutomator Address of the vault automator
  /// @param wrapAsset wrap asset
  function initialize(
    VaultCreateParams memory params,
    address _owner,
    address _vaultAutomator,
    Asset memory wrapAsset
  ) public initializer {
    require(params.principalToken != address(0), ZeroAddress());

    __ERC20_init(params.name, params.symbol);
    __ERC20Permit_init(params.name);
    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(ADMIN_ROLE_HASH, _owner);
    _grantRole(ADMIN_ROLE_HASH, _vaultAutomator);

    principalToken = params.principalToken;

    for (uint256 i = 0; i < params.assets.length; i++) {
      require(params.assets[i].token != address(0), ZeroAddress());
      require(params.assets[i].amount != 0, InvalidAssetAmount());
      require(IERC20(params.assets[i].token).balanceOf(address(this)) >= params.assets[i].amount, InvalidAssetAmount());

      currentAssets[params.assets[i].token][params.assets[i].tokenId] = params.assets[i];
    }

    if (wrapAsset.amount > 0) {
      currentAssets[wrapAsset.token][wrapAsset.tokenId] = wrapAsset;
    }
  }

  /// @notice Deposits the asset to the vault
  /// @param amount Amount to deposit
  function deposit(uint256 amount) external returns (uint256 shares) {}

  /// @notice Deposits the principal to the vault
  /// @param amount Amount to deposit
  function depositPrinciple(uint256 amount) external returns (uint256 shares) {}

  /// @notice Allocates the assets to the strategy
  /// @param inputAssets Input assets to allocate
  /// @param strategy Strategy to allocate to
  /// @param data Data for the strategy
  function allocate(Asset[] memory inputAssets, IStrategy strategy, bytes calldata data) external {
    Asset memory currentAsset;
    for (uint256 i = 0; i < inputAssets.length; i++) {
      require(inputAssets[i].amount != 0, InvalidAssetAmount());
      currentAsset = currentAssets[inputAssets[i].token][inputAssets[i].tokenId];
      require(currentAsset.amount >= inputAssets[i].amount, InvalidAssetAmount());
      currentAsset.amount -= inputAssets[i].amount;

      currentAssets[currentAsset.token][currentAsset.tokenId] = currentAsset;
      inputAssets[i].strategy = currentAsset.strategy;
    }

    Asset[] memory newAssets = strategy.convert(inputAssets, data);
    for (uint256 i = 0; i < newAssets.length; i++) {
      currentAsset = currentAssets[newAssets[i].token][newAssets[i].tokenId];
      currentAsset.amount += newAssets[i].amount;

      currentAssets[currentAsset.token][currentAsset.tokenId] = currentAsset;
    }
  }

  /// @notice Deallocates the assets from the strategy
  /// @param strategy Strategy to deallocate from
  /// @param allocationAmount Amount to deallocate
  function deallocate(IStrategy strategy, uint256 allocationAmount) external {}

  /// @notice Returns the total value of the vault
  function getTotalValue() external returns (uint256) {}

  /// @notice Returns the asset allocations of the vault
  function getAssetAllocations() external returns (Asset[] memory assets, uint256[] memory values) {}
}
