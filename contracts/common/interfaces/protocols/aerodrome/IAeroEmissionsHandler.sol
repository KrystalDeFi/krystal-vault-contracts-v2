// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Aero's leaf-chain emissions handler, which pays emissions in the receipt token. Base's (root) handler redeems
///         them for AERO instead and has no `RECEIPT_TOKEN()`.
interface IAeroEmissionsHandler {
  function RECEIPT_TOKEN() external view returns (address);
}
