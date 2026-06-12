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
import "../../public-vault/interfaces/IWETH9.sol";

contract SharedVaultFactory is OwnableUpgradeable, PausableUpgradeable, Withdrawable, ISharedVaultFactory {
  using SafeERC20 for IERC20;

  ISharedConfigManager public configManager;
  address public vaultImplementation;
  address public weth;

  mapping(address => address[]) public vaultsByAddress;

  address[] public allVaults;
  mapping(address => bool) public isVaultAddress;

  function initialize(
    address _owner,
    address _configManager,
    address _vaultImplementation,
    address _weth
  ) external initializer {
    require(
      _owner != address(0) && _configManager != address(0) && _vaultImplementation != address(0) && _weth != address(0),
      ZeroAddress()
    );

    __Ownable_init(_owner);
    __Pausable_init();

    configManager = ISharedConfigManager(_configManager);
    vaultImplementation = _vaultImplementation;
    weth = _weth;
  }

  /// @notice Create a shared vault with initial token deposits
  /// @dev Send ETH via msg.value to auto-wrap to WETH for the initial deposit
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    uint16 vaultOwnerFeeBasisPoint
  ) external payable override whenNotPaused returns (address vault) {
    vault = _createVault(name, tokens, initialAmounts, _msgSender(), vaultOwnerFeeBasisPoint);
  }

  /// @notice Create a shared vault with initial deposits and run `execute(actions)` once
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    uint16 vaultOwnerFeeBasisPoint,
    ISharedVault.Action[] calldata actions
  ) external payable override whenNotPaused returns (address vault) {
    vault = _createVault(name, tokens, initialAmounts, address(this), vaultOwnerFeeBasisPoint);

    if (actions.length > 0) {
      ISharedVault(vault).execute(actions);
    }

    ISharedVault(vault).transferOwnership(_msgSender());

    // INITIAL_SHARES were minted to address(this) as the temporary vaultOwner during init.
    // Transfer them to the actual caller now that setup is complete.
    uint256 sharesBal = IERC20(vault).balanceOf(address(this));
    if (sharesBal > 0) {
      IERC20(vault).safeTransfer(_msgSender(), sharesBal);
    }
  }

  function _createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    uint16 _vaultOwnerFeeBasisPoint
  ) internal returns (address vault) {
    bytes32 salt = keccak256(abi.encodePacked(name, _msgSender(), "shared-1.0"));
    address predicted = Clones.predictDeterministicAddress(vaultImplementation, salt);
    require(predicted.code.length == 0, DuplicateVaultName());
    vault = Clones.cloneDeterministic(vaultImplementation, salt);

    // Wrap ETH to WETH and transfer to vault if ETH was provided for the initial deposit
    if (msg.value > 0) {
      bool foundWeth;
      for (uint256 i; i < 4; ) {
        if (tokens[i] == weth) {
          require(initialAmounts[i] == msg.value, InvalidAmount());
          foundWeth = true;
          break;
        }
        unchecked {
          i++;
        }
      }
      require(foundWeth, TokenNotConfigured());
      IWETH9(weth).deposit{ value: msg.value }();
      IERC20(weth).safeTransfer(vault, msg.value);
    }

    // Transfer remaining initial tokens to vault before initialization
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0) && initialAmounts[i] > 0) {
        if (msg.value > 0 && tokens[i] == weth) {
          // WETH already transferred above via ETH wrap
        } else {
          IERC20(tokens[i]).safeTransferFrom(_msgSender(), vault, initialAmounts[i]);
        }
      }
      unchecked {
        i++;
      }
    }

    ISharedVault(vault).initialize(
      name,
      tokens,
      initialAmounts,
      _owner,
      owner(),
      address(configManager),
      weth,
      _vaultOwnerFeeBasisPoint
    );

    vaultsByAddress[_msgSender()].push(vault);
    allVaults.push(vault);
    isVaultAddress[vault] = true;

    emit VaultCreated(_msgSender(), vault, name);
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
