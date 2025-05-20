// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "../IStrategy.sol";

interface IKodiakIslandStrategy is IStrategy {
  // Custom errors
  error InvalidAssetStrategy();
  error InvalidIslandFactory();
  error InvalidPrincipalToken();

  struct SwapAndStakeParams {
    address bgtRewardVault;
  }

  struct WithdrawAndSwapParams {
    uint256 minPrincipalAmount;
  }

  enum InstructionType {
    SwapAndStake,
    WithdrawAndSwap
  }
}
