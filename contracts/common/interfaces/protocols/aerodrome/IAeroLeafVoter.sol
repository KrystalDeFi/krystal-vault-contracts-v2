// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Aero's per-chain LeafVoter: settles gauge emissions and mints them as its receipt token (xAERO), which the
///         emissions handler then delivers.
interface IAeroLeafVoter {
  /// @notice Whether `gauge` is activated; an inactive gauge earns no emissions
  function isActivated(address gauge) external view returns (bool);

  function RECEIPT_TOKEN() external view returns (address);

  /// @notice Leaf chains' handler transfers the receipt token to the recipient; Base's redeems it for AERO instead
  function EMISSIONS_HANDLER() external view returns (address);
}
