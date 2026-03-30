// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedConfigManager {
  event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
  event WhitelistTargetsUpdated(address[] targets, bool isWhitelisted);
  event WhitelistCallersUpdated(address[] callers, bool isWhitelisted);
  event VaultPausedUpdated(bool isVaultPaused);

  function isVaultPaused() external view returns (bool);

  function feeRecipient() external view returns (address);

  // Target whitelist (for strategy delegatecalls and swap aggregator calls)
  function isWhitelistedTarget(address target) external view returns (bool);

  function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external;

  // Caller whitelist (authorized callers besides owner/admin)
  function isWhitelistedCaller(address caller) external view returns (bool);

  function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external;

  function setVaultPaused(bool _isVaultPaused) external;

  function setFeeRecipient(address newFeeRecipient) external;
}
