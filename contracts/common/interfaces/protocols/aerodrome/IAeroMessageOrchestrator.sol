// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Aero's per-chain message orchestrator for redeems. On Base its adapter is the root-local adapter; on the
///         other chains it is a cross-chain (Hyperlane) adapter.
interface IAeroMessageOrchestrator {
  function adapter() external view returns (address);
}
