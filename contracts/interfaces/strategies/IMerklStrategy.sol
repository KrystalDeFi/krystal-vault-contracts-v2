// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "./IStrategy.sol";

interface IMerklStrategy is IStrategy {
  error NotEnoughAmountOut();
  error ApproveFailed();
  error SwapFailed();
  error InvalidSigner();
  error SignatureExpired();

  enum InstructionType {
    ClaimAndSwap
  }

  struct ClaimAndSwapParams {
    address distributor;
    address token;
    uint256 amount;
    bytes32[] proof;
    address swapRouter;
    bytes swapData;
    uint256 amountOutMin;
    uint32 deadline;
    bytes signature;
  }
}
