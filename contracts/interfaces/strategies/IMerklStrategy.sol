// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "./IStrategy.sol";

interface IMerklStrategy is IStrategy {
  error NotEnoughAmountOut();

  enum InstructionType {
    ClaimAndSwap
  }

  struct ClaimAndSwapParams {
    address distributor;
    address token;
    uint256 amount;
    bytes32[] proof;
    bytes swapData;
    uint256 amountOutMin;
  }
}
