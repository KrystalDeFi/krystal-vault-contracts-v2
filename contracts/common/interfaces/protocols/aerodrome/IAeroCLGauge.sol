// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice The Aero-only surface of a CL gauge of Aero, the merged Aerodrome + Velodrome protocol (MetaDEX Slipstream).
///         `deposit`, `withdraw` and `stakedContains` keep the legacy CLGauge selectors (see ICLGauge), but emissions
///         are claimed with `claimEmissions` (there is no `getReward` or `rewardToken`) and paid by the LeafVoter: AERO
///         on Base, xAERO elsewhere. Claims and withdrawals pay emissions net of the gauge's early-stake penalty and of
///         its referral share.
interface IAeroCLGauge {
  /// @notice Claim the emissions of `tokenIds` staked by `account`, plus all of the account's deferred emissions.
  /// @dev Callable by `account` or an operator it approved for claims. Reverts when a listed tokenId is not staked by
  ///      `account`, when the list is empty and nothing is deferred, or when minting the emissions fails.
  function claimEmissions(address account, address recipient, uint256[] calldata tokenIds) external;

  /// @notice Emissions stored for `account` because minting them failed while it withdrew a position
  function deferredEmissions(address account) external view returns (uint256);

  /// @notice Unstake a position owned by the caller without settling its emissions, which are forfeited.
  /// @dev Reverts unless the gauge factory's `emergencyWithdrawEnabled()` is on. Aero gauges from v1.1.0 only: Arc's
  ///      pre-merger ("lite") gauges don't have it.
  function emergencyWithdraw(uint256 tokenId) external;
}
