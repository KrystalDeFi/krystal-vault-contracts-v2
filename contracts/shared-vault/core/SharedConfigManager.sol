// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/ISharedConfigManager.sol";
import "../interfaces/ISharedCommon.sol";

contract SharedConfigManager is OwnableUpgradeable, ISharedConfigManager {
  mapping(address => bool) public whitelistedTargets;
  mapping(address => bool) public whitelistedCallers;

  bool public override isVaultPaused = false;
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
      whitelistedTargets[_whitelistTargets[i]] = true;
      unchecked { i++; }
    }

    length = _whitelistCallers.length;
    for (uint256 i; i < length;) {
      whitelistedCallers[_whitelistCallers[i]] = true;
      unchecked { i++; }
    }

    feeRecipient = _feeRecipient;

    if (_whitelistTargets.length > 0) emit WhitelistTargetsUpdated(_whitelistTargets, true);
    if (_whitelistCallers.length > 0) emit WhitelistCallersUpdated(_whitelistCallers, true);
  }

  function setWhitelistTargets(address[] calldata targets, bool _isWhitelisted) external override onlyOwner {
    uint256 length = targets.length;
    for (uint256 i; i < length;) {
      whitelistedTargets[targets[i]] = _isWhitelisted;
      unchecked { i++; }
    }
    emit WhitelistTargetsUpdated(targets, _isWhitelisted);
  }

  function isWhitelistedTarget(address target) external view override returns (bool) {
    return whitelistedTargets[target];
  }

  function setWhitelistCallers(address[] calldata callers, bool _isWhitelisted) external override onlyOwner {
    uint256 length = callers.length;
    for (uint256 i; i < length;) {
      whitelistedCallers[callers[i]] = _isWhitelisted;
      unchecked { i++; }
    }
    emit WhitelistCallersUpdated(callers, _isWhitelisted);
  }

  function isWhitelistedCaller(address caller) external view override returns (bool) {
    return whitelistedCallers[caller];
  }

  function setVaultPaused(bool _isVaultPaused) external onlyOwner {
    isVaultPaused = _isVaultPaused;
    emit VaultPausedUpdated(_isVaultPaused);
  }

  function setFeeRecipient(address newFeeRecipient) external override onlyOwner {
    require(newFeeRecipient != address(0), ISharedCommon.ZeroAddress());

    emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);

    feeRecipient = newFeeRecipient;
  }
}
