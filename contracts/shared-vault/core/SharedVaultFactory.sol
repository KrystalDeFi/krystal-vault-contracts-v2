// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/ISharedVaultFactory.sol";
import "../interfaces/ISharedVault.sol";
import "../interfaces/ISharedConfigManager.sol";
import "../../common/Withdrawable.sol";

contract SharedVaultFactory is OwnableUpgradeable, PausableUpgradeable, Withdrawable, ISharedVaultFactory {
  using SafeERC20 for IERC20;

  ISharedConfigManager public configManager;
  address public vaultImplementation;

  mapping(address => address[]) public vaultsByAddress;

  address[] public allVaults;
  mapping(address => bool) public isVaultAddress;

  function initialize(address _owner, address _configManager, address _vaultImplementation) external initializer {
    require(
      _owner != address(0) && _configManager != address(0) && _vaultImplementation != address(0), ZeroAddress()
    );

    __Ownable_init(_owner);
    __Pausable_init();

    configManager = ISharedConfigManager(_configManager);
    vaultImplementation = _vaultImplementation;
  }

  /// @notice Create a shared vault with initial token deposits
  function createVault(
    string calldata name,
    string calldata symbol,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts
  ) external override whenNotPaused returns (address vault) {
    vault = _createVault(name, symbol, tokens, initialAmounts);
  }

  /// @notice Create a shared vault with initial deposits and execute a strategy
  function createVault(
    string calldata name,
    string calldata symbol,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    address strategy,
    bytes calldata strategyData
  ) external payable override whenNotPaused returns (address vault) {
    vault = _createVault(name, symbol, tokens, initialAmounts);

    if (strategyData.length > 0) {
      ISharedVault(vault).execute{ value: msg.value }(strategy, strategyData);
    }
  }

  function _createVault(
    string calldata name,
    string calldata symbol,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts
  ) internal returns (address vault) {
    vault = Clones.cloneDeterministic(
      vaultImplementation, keccak256(abi.encodePacked(name, symbol, msg.sender, "shared-1.0"))
    );

    // Transfer initial tokens to vault before initialization
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0) && initialAmounts[i] > 0) {
        IERC20(tokens[i]).safeTransferFrom(msg.sender, vault, initialAmounts[i]);
      }
      unchecked { i++; }
    }

    ISharedVault(vault).initialize(name, symbol, tokens, initialAmounts, msg.sender, address(configManager));

    vaultsByAddress[msg.sender].push(vault);
    allVaults.push(vault);
    isVaultAddress[vault] = true;

    emit VaultCreated(msg.sender, vault, name);
  }

  /// @notice Check if a vault was created by this factory
  function isVault(address vault) external view override returns (bool) {
    return isVaultAddress[vault];
  }

  /// @notice Get all vaults created by an address
  function getVaultsByAddress(address owner) external view returns (address[] memory) {
    return vaultsByAddress[owner];
  }

  /// @notice Get total number of vaults
  function allVaultsLength() external view returns (uint256) {
    return allVaults.length;
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function setConfigManager(address _configManager) external onlyOwner {
    require(_configManager != address(0), ZeroAddress());
    configManager = ISharedConfigManager(_configManager);
    emit ConfigManagerSet(_configManager);
  }

  function setVaultImplementation(address _vaultImplementation) external onlyOwner {
    require(_vaultImplementation != address(0), ZeroAddress());
    vaultImplementation = _vaultImplementation;
    emit VaultImplementationSet(_vaultImplementation);
  }

  /// @inheritdoc Withdrawable
  function _checkWithdrawPermission() internal view override {
    _checkOwner();
  }
}
