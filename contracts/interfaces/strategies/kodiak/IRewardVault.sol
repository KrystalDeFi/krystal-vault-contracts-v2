// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IRewardVault {
  function factory() external view returns (address);

  function stakeToken() external view returns (address);

  function rewardToken() external view returns (address);

  function rewards(address account) external view returns (uint256);

  function earned(address account) external view returns (uint256);

  function stake(uint256 amount) external;

  function withdraw(uint256 amount) external;

  function exit(address recipient) external;

  function getReward(address account, address recipient) external returns (uint256);
}
