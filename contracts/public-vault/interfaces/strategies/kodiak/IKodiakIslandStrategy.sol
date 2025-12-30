// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "../IStrategy.sol";

interface IKodiakIslandStrategy is IStrategy {
  event BgtRewardClaim(uint256 amount);
  // Custom errors

  error InvalidAssetStrategy();
  error InvalidPrincipalToken();
  error InvalidRewardVault();

  struct SwapAndStakeParams {
    address kodiakIslandLpAddress;
  }

  struct WithdrawAndSwapParams {
    uint256 minPrincipalAmount;
  }

  enum InstructionType {
    SwapAndStake,
    WithdrawAndSwap
  }
}
