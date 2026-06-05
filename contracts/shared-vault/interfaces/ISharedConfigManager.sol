// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedConfigManager {
  event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
  event PlatformFeeBasisPointUpdated(uint16 basisPoints);
  event WhitelistTargetsUpdated(address[] targets, bool isWhitelisted);
  event WhitelistCallersUpdated(address[] callers, bool isWhitelisted);
  event WhitelistNfpmsUpdated(address[] nfpms, bool isWhitelisted);
  event WhitelistSwapRoutersUpdated(address[] swapRouters, bool isWhitelisted);
  event WhitelistSignersUpdated(address[] signers, bool isWhitelisted);
  event VaultPausedUpdated(bool isVaultPaused);
  event MaxPositionsUpdated(uint16 maxPositions);
  event MinTokenPrecisionUpdated(uint8 precision);
  event MaxGasFeeX64Updated(uint64 maxGasFeeX64);

  function isVaultPaused() external view returns (bool);

  function feeRecipient() external view returns (address);

  /// @notice Platform fee on LP performance collections (basis points), sent to `feeRecipient` when LP fees are settled.
  function platformFeeBasisPoint() external view returns (uint16);

  function setPlatformFeeBasisPoint(uint16 basisPoints) external;

  /// @notice Maximum executor gas-fee fraction accepted from shared strategy calldata.
  /// @dev Q64 fixed point: 2**64 is 100%, but the uint64 field can represent up to just below 100%.
  ///      Default is 30%; the config owner can lower it to 0 to disable discretionary strategy gas fees.
  function maxGasFeeX64() external view returns (uint64);

  function setMaxGasFeeX64(uint64 maxGasFeeX64) external;

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

  // Signer whitelist (backend signers allowed to authorize off-chain validated payloads)
  function isWhitelistedSigner(address signer) external view returns (bool);

  function setWhitelistSigners(address[] calldata signers, bool isWhitelisted) external;

  function setVaultPaused(bool _isVaultPaused) external;

  function setFeeRecipient(address newFeeRecipient) external;

  /// @notice Maximum number of LP positions a vault may hold simultaneously.
  ///         Limits the per-deposit and per-withdraw loop cost. Default: 20.
  function maxPositions() external view returns (uint16);

  function setMaxPositions(uint16 _maxPositions) external;

  /// @notice Decimal-place precision that defines the protocol-wide dust floor.
  ///         The effective minimum amount for any token is:
  ///
  ///             minAmt = 10 ** max(0, token.decimals() - minTokenPrecision)
  ///
  ///         Examples with the default precision of 5 (= 0.00001 of any token):
  ///           USDC  (6 dec)  → 10 ** (6-5)  = 10        ≈ 0.00001 USDC
  ///           WBTC  (8 dec)  → 10 ** (8-5)  = 1 000     ≈ 0.00001 BTC  (1000 sats)
  ///           WETH  (18 dec) → 10 ** (18-5) = 10 000 000 000 000  ≈ 0.00001 ETH
  ///
  ///         This approach makes the floor token-agnostic: one configured value scales
  ///         correctly for every token regardless of its decimal precision.
  ///
  ///         Protects against two dust-related issues:
  ///         1. DEPOSIT DILUTION ATTACK — floor-division rounds a depositor's tiny proportional
  ///            slice to zero, letting them receive shares without contributing to every asset.
  ///            SharedVault rounds slices UP (ceiling) and then raises to the computed min,
  ///            so the depositor always over-pays for sub-threshold slices.
  ///         2. GATEWAY SWAP FAILURES — swap aggregators reject micro amounts. The floor ensures
  ///            every proportional slice is large enough for an aggregator to process.
  ///
  ///         A value of 0 disables the floor (only ceiling rounding remains active).
  function minTokenPrecision() external view returns (uint8);

  /// @notice Set the dust-floor precision level.
  ///         5 → 0.00001 of any token (default).
  ///         0 → floor disabled (ceiling rounding still prevents the dilution attack).
  function setMinTokenPrecision(uint8 precision) external;
}
