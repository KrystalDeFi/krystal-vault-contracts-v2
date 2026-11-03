// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @dev The reward forward of V3Utils since v3utils#63: the reward it passes on for a position manager's positions.
interface IV3UtilsRewardForward {
  function positionRewardToken(address nfpm) external view returns (address);
}
