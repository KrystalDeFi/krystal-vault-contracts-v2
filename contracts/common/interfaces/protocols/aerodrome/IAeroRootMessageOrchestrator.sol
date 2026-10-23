// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Aero's root (Base) message orchestrator, which delivers redeems to the Voter.
interface IAeroRootMessageOrchestrator {
  function VOTER() external view returns (address);
}
