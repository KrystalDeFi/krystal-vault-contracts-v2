// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/IVaultFactory.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IWETH9.sol";

/// @title VaultFactory
contract VaultFactory is Ownable, Pausable, IVaultFactory {
  using SafeERC20 for IERC20;

  address public WETH;
  address public vaultImplementation;
  address public vaultAutomator;
  address public platformFeeRecipient;
  uint16 public platformFeeBasisPoint;

  mapping(address => address[]) public vaultsByAddress;

  address[] public allVaults;

  constructor(
    address _weth,
    address _vaultImplementation,
    address _vaultAutomator,
    address _platformFeeRecipient,
    uint16 _platformFeeBasisPoint
  ) Ownable(_msgSender()) {
    require(_weth != address(0), ZeroAddress());
    require(_vaultImplementation != address(0), ZeroAddress());
    require(_vaultAutomator != address(0), ZeroAddress());
    require(_platformFeeRecipient != address(0), ZeroAddress());

    WETH = _weth;
    vaultImplementation = _vaultImplementation;
    vaultAutomator = _vaultAutomator;
    platformFeeRecipient = _platformFeeRecipient;
    platformFeeBasisPoint = _platformFeeBasisPoint;
  }

  /// @notice Create a new vault
  /// @param params Vault creation parameters
  /// @return vault Address of the new vault
  function createVault(
    VaultCreateParams memory params
  ) external payable override whenNotPaused returns (address vault) {
    require(params.ownerFeeBasisPoint <= 1000, InvalidOwnerFee());

    vault = Clones.clone(vaultImplementation);

    if (msg.value > 0) {
      require(params.principalToken == WETH, InvalidPrincipalToken());
      params.principalTokenAmount = msg.value;
      IWETH9(WETH).deposit{ value: msg.value }();
    }

    IVault(vault).initialize(params, _msgSender(), vaultAutomator);

    vaultsByAddress[_msgSender()].push(vault);
    allVaults.push(vault);

    emit VaultCreated();
  }

  /// @notice Pause the contract
  function pause() public onlyOwner {
    _pause();
  }

  /// @notice Unpause the contract
  function unpause() public onlyOwner {
    _unpause();
  }

  /// @notice Set the Vault implementation
  /// @param _vaultImplementation Address of the new vault implementation
  function setVaultImplementation(address _vaultImplementation) public onlyOwner {
    require(_vaultImplementation != address(0), ZeroAddress());
    vaultImplementation = _vaultImplementation;
  }

  /// @notice Set the VaultAutomator address
  function setVaultAutomator(address _vaultAutomator) public onlyOwner {
    require(_vaultAutomator != address(0), ZeroAddress());
    vaultAutomator = _vaultAutomator;
  }

  /// @notice Set the default platform fee recipient
  function setPlatformFeeRecipient(address _platformFeeRecipient) public onlyOwner {
    require(_platformFeeRecipient != address(0), ZeroAddress());
    platformFeeRecipient = _platformFeeRecipient;
  }

  /// @notice Set the default platform fee basis point
  function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) public onlyOwner {
    platformFeeBasisPoint = _platformFeeBasisPoint;
  }
}
