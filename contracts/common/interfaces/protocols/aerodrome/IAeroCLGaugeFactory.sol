// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice CL gauge factory of Aero (MetaDEX Slipstream). Legacy Aerodrome/Velodrome CLGaugeFactory contracts don't have
///         `leafVoter()`, which is what tells the two apart.
interface IAeroCLGaugeFactory {
  function leafVoter() external view returns (address);

  /// @notice Emission cap of `gauge`; a gauge with a zero cap earns no emissions
  function emissionCap(address gauge) external view returns (uint128);
}
