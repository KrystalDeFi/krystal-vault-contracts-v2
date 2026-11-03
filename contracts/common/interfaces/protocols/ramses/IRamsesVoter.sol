// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice The parts of Ramses' Voter the vault strategies read. Each Ramses deployment has one Voter, wired to its
///         single CL position manager.
interface IRamsesVoter {
  /// @notice The CL position manager whose positions this Voter's gauges reward.
  function nfpManager() external view returns (address);

  /// @notice The token gauges pay emissions in.
  function ram() external view returns (address);

  /// @notice The gauge of `pool`, zero for a pool without one (fee-only).
  function gaugeForPool(address pool) external view returns (address);
}
