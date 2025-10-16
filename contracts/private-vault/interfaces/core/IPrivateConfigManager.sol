// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IPrivateConfigManager {
  event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

  function isVaultPaused() external view returns (bool);

  function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external;

  function isWhitelistedTarget(address target) external view returns (bool);

  function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external;

  function isWhitelistedCaller(address caller) external view returns (bool);

  function setVaultPaused(bool _isVaultPaused) external;

  function enforceTargetWhitelistForOwners() external view returns (bool);

  function setEnforceTargetWhitelistForOwners(bool _enforceTargetWhitelistForOwners) external;

  function feeRecipient() external view returns (address);

  function setFeeRecipient(address newFeeRecipient) external;
}
