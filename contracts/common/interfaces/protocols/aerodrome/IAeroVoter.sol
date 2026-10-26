// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Aero's root Voter on Base; redeemed emissions are paid in its TOKEN (AERO).
interface IAeroVoter {
  function TOKEN() external view returns (address);
}
