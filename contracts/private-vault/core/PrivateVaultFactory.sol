// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/core/IPrivateVaultFactory.sol";
import "../interfaces/core/IPrivateVault.sol";

contract PrivateVaultFactory is OwnableUpgradeable, PausableUpgradeable, IPrivateVaultFactory {
  using SafeERC20 for IERC20;

  address public configManager;
  address public vaultImplementation;

  mapping(address => address[]) public vaultsByAddress;

  address[] public allVaults;
  mapping(address => bool) public isVaultAddress;

  function initialize(address _owner, address _configManager, address _vaultImplementation) external initializer {
    require(_owner != address(0) && _configManager != address(0) && _vaultImplementation != address(0), ZeroAddress());

    __Ownable_init(_owner);
    __Pausable_init();

    configManager = _configManager;
    vaultImplementation = _vaultImplementation;
  }

  function createVault(bytes32 salt) external payable override whenNotPaused returns (address vault) {
    vault = Clones.cloneDeterministic(vaultImplementation, keccak256(abi.encodePacked(msg.sender, salt)));

    IPrivateVault(vault).initialize(msg.sender, configManager);

    vaultsByAddress[msg.sender].push(vault);
    allVaults.push(vault);
    isVaultAddress[vault] = true;

    emit VaultCreated(msg.sender, vault, salt);
  }

  function createVault(
    bytes32 salt,
    address[] calldata tokens,
    uint256[] calldata amounts,
    address[] calldata nfts721,
    uint256[] calldata nfts721TokenIds,
    address[] calldata nfts1155,
    uint256[] calldata nfts1155TokenIds,
    uint256[] calldata nfts1155Amounts,
    address[] calldata targets,
    bytes[] calldata data,
    CallType[] calldata callTypes
  ) external payable override whenNotPaused returns (address vault) {
    vault = Clones.cloneDeterministic(vaultImplementation, keccak256(abi.encodePacked(msg.sender, salt)));

    IPrivateVault(vault).initialize(msg.sender, configManager);

    if (msg.value > 0) {
      (bool success,) = vault.call{ value: msg.value }("");
      require(success, "Failed to send native token");
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i]).safeTransferFrom(msg.sender, vault, amounts[i]);
    }

    for (uint256 i = 0; i < nfts721.length; i++) {
      IERC721(nfts721[i]).safeTransferFrom(msg.sender, vault, nfts721TokenIds[i]);
    }

    for (uint256 i = 0; i < nfts1155.length; i++) {
      IERC1155(nfts1155[i]).safeTransferFrom(msg.sender, vault, nfts1155TokenIds[i], nfts1155Amounts[i], "");
    }

    IPrivateVault(vault).multicall(targets, data, callTypes);

    vaultsByAddress[msg.sender].push(vault);
    allVaults.push(vault);
    isVaultAddress[vault] = true;

    emit VaultCreated(msg.sender, vault, salt);
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
    return isVaultAddress[vault];
  }
}
