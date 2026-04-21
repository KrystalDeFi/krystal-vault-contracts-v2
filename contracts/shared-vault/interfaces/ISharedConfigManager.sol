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
  event MinTokenAmountUpdated(uint256 minTokenAmount);

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

  /// @notice Global minimum "swappable" amount enforced uniformly on every vault token during
  ///         proportional deposit/withdraw computations. A single protocol-wide value is used
  ///         rather than a per-token mapping because the config owner does not control which
  ///         tokens any given vault is created with. Protects against two dust-related issues:
  ///
  ///         1. DEPOSIT DILUTION ATTACK — without a minimum, when a vault holds tiny balances of
  ///            some token (e.g. 50 wei of USDT alongside 100e18 of another token), floor-division
  ///            rounds the depositor's proportional slice of that dust token down to zero. The
  ///            depositor then receives shares without paying for the dust token — dilution over
  ///            many small deposits. SharedVault rounds the proportional slice UP and then raises
  ///            it to `minTokenAmount` on deposit, so the depositor always overpays for sub-min
  ///            slices (existing holders protected).
  ///
  ///         2. GATEWAY SWAP FAILURES — swap aggregators cannot produce/consume micro amounts
  ///            (e.g. 1 wei of USDT). SharedVaultGateway therefore cannot fulfill proportional
  ///            deposits or swap back proportional withdrawals when a slice is sub-threshold.
  ///            Setting a modest floor (e.g. 10 base units) ensures the gateway always sees
  ///            swappable amounts, regardless of the underlying token's decimals.
  ///
  ///         Unit: raw base units (wei-like). A value of 0 disables the minimum entirely and
  ///         restores the legacy floor-division behaviour.
  function minTokenAmount() external view returns (uint256);

  /// @notice Set the global minimum token amount. Pass 0 to disable the minimum.
  function setMinTokenAmount(uint256 _minTokenAmount) external;
}
