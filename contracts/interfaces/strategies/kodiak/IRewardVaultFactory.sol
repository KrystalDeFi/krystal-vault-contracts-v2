// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IRewardVaultFactory {
  function getVault(address stakingToken) external view returns (address);
}
