// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Aero's Base-only adapter that hands Base's redeems to the root message orchestrator in the same transaction.
interface IAeroRootLocalAdapter {
  function ROOT_MESSAGE_ORCHESTRATOR() external view returns (address);
}
