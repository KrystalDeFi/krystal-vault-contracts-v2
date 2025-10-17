// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/core/IPrivateConfigManager.sol";

contract PrivateConfigManager is OwnableUpgradeable, IPrivateConfigManager {
  mapping(address => bool) public whitelistTargets;
  mapping(address => bool) public whitelistCallers;

  bool public override isVaultPaused = false;
  bool public override enforceTargetWhitelistForOwners = false;
  address public override feeRecipient;

  function initialize(
    address _owner,
    address[] calldata _whitelistTargets,
    address[] calldata _whitelistCallers,
    address _feeRecipient
  ) public initializer {
    __Ownable_init(_owner);

    uint256 length = _whitelistTargets.length;
    for (uint256 i; i < length;) {
      whitelistTargets[_whitelistTargets[i]] = true;
      i++;
    }

    length = _whitelistCallers.length;
    for (uint256 i; i < length;) {
      whitelistCallers[_whitelistCallers[i]] = true;
      i++;
    }

    feeRecipient = _feeRecipient;
  }

  function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external override onlyOwner {
    uint256 length = targets.length;
    for (uint256 i; i < length;) {
      whitelistTargets[targets[i]] = isWhitelisted;
      i++;
    }
  }

  function isWhitelistedTarget(address target) external view override returns (bool) {
    return whitelistTargets[target];
  }

  function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external override onlyOwner {
    uint256 length = callers.length;
    for (uint256 i; i < length;) {
      whitelistCallers[callers[i]] = isWhitelisted;
      i++;
    }
  }

  function isWhitelistedCaller(address caller) external view override returns (bool) {
    return whitelistCallers[caller];
  }

  function setVaultPaused(bool _isVaultPaused) external onlyOwner {
    isVaultPaused = _isVaultPaused;
  }

  function setEnforceTargetWhitelistForOwners(bool _enforceTargetWhitelistForOwners) external override onlyOwner {
    enforceTargetWhitelistForOwners = _enforceTargetWhitelistForOwners;
  }

  function setFeeRecipient(address newFeeRecipient) external override onlyOwner {
    require(newFeeRecipient != address(0), "ZeroAddress");

    emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);

    feeRecipient = newFeeRecipient;
  }
}
