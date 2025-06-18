// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/core/IVaultFactory.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/IWETH9.sol";

/// @title VaultFactory
contract VaultFactory is OwnableUpgradeable, PausableUpgradeable, IVaultFactory {
  using SafeERC20 for IERC20;

  address public override WETH;
  address public configManager;
  address public vaultImplementation;

  mapping(address => address[]) public vaultsByAddress;

  address[] public allVaults;

  function initialize(address _owner, address _weth, address _configManager, address _vaultImplementation)
    external
    initializer
  {
    require(
      _owner != address(0) && _weth != address(0) && _configManager != address(0) && _vaultImplementation != address(0),
      ZeroAddress()
    );

    __Ownable_init(_owner);
    __Pausable_init();

    WETH = _weth;
    configManager = _configManager;
    vaultImplementation = _vaultImplementation;
  }

  /// @notice Create a new vault
  /// @param params Vault creation parameters
  /// @return vault Address of the new vault
  function createVault(VaultCreateParams memory params) external payable override whenNotPaused returns (address vault) {
    vault = Clones.cloneDeterministic(
      vaultImplementation, keccak256(abi.encodePacked(params.name, params.symbol, _msgSender()))
    );

    address sender = _msgSender();
    address principalToken = params.config.principalToken;
    uint256 principalAmount = params.principalTokenAmount;

    if (msg.value > 0) {
      require(principalToken == WETH && principalAmount == msg.value, InvalidPrincipalToken());
      IWETH9(WETH).deposit{ value: msg.value }();
      IERC20(WETH).safeTransfer(vault, msg.value);
    } else if (principalAmount > 0) {
      IERC20(principalToken).safeTransferFrom(sender, vault, principalAmount);
    }

    IVault(vault).initialize(params, sender, owner(), configManager, WETH);

    vaultsByAddress[sender].push(vault);
    allVaults.push(vault);

    emit VaultCreated(sender, vault, params);
  }

  /// @notice Pause the contract
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Unpause the contract
  function unpause() external onlyOwner {
    _unpause();
  }

  /// @notice Set the ConfigManager address
  /// @param _configManager Address of the new ConfigManager
  function setConfigManager(address _configManager) external onlyOwner {
    require(_configManager != address(0), ZeroAddress());
    configManager = _configManager;
    emit ConfigManagerSet(_configManager);
  }

  /// @notice Set the Vault implementation
  /// @param _vaultImplementation Address of the new vault implementation
  function setVaultImplementation(address _vaultImplementation) external onlyOwner {
    require(_vaultImplementation != address(0), ZeroAddress());
    vaultImplementation = _vaultImplementation;
    emit VaultImplementationSet(_vaultImplementation);
  }

  /// @notice Check if a vault created by this factory
  /// @param vault Address of the vault to check
  function isVault(address vault) external view override returns (bool) {
    for (uint256 i = 0; i < allVaults.length; i++) {
      if (allVaults[i] == vault) return true;
    }
    return false;
  }
}
