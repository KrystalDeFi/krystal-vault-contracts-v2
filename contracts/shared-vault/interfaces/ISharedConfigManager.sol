// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedConfigManager {
  event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
  event WhitelistTargetsUpdated(address[] targets, bool isWhitelisted);
  event WhitelistCallersUpdated(address[] callers, bool isWhitelisted);
  event WhitelistNfpmsUpdated(address[] nfpms, bool isWhitelisted);
  event WhitelistSwapRoutersUpdated(address[] swapRouters, bool isWhitelisted);
  event VaultPausedUpdated(bool isVaultPaused);
  event MaxPositionsUpdated(uint16 maxPositions);

  function isVaultPaused() external view returns (bool);

  function feeRecipient() external view returns (address);

  /// @notice Platform fee on LP performance collections (basis points), sent to `feeRecipient` via `LpFeeTaker` on exit.
  function platformFeeBasisPoint() external view returns (uint16);

  function setPlatformFeeBasisPoint(uint16 basisPoints) external;

  // Target whitelist (for strategy delegatecalls and swap aggregator calls)
  function isWhitelistedTarget(address target) external view returns (bool);

  function setWhitelistTargets(address[] calldata targets, bool isWhitelisted) external;

  // Caller whitelist (authorized callers besides owner/admin)
  function isWhitelistedCaller(address caller) external view returns (bool);

  function setWhitelistCallers(address[] calldata callers, bool isWhitelisted) external;

  // NFPM whitelist (allowed NFT position managers for LP positions)
  function isWhitelistedNfpm(address nfpm) external view returns (bool);

  function setWhitelistNfpms(address[] calldata nfpms, bool isWhitelisted) external;

  // Swap router whitelist (allowed swap aggregators for CALL actions)
  function isWhitelistedSwapRouter(address swapRouter) external view returns (bool);

  function setWhitelistSwapRouters(address[] calldata swapRouters, bool isWhitelisted) external;

  function setVaultPaused(bool _isVaultPaused) external;

  function setFeeRecipient(address newFeeRecipient) external;

  /// @notice Maximum number of LP positions a vault may hold simultaneously.
  ///         Limits the per-deposit and per-withdraw loop cost. Default: 20.
  function maxPositions() external view returns (uint16);

  function setMaxPositions(uint16 _maxPositions) external;
}
