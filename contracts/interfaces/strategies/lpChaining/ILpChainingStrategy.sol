// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ILpStrategy.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface ILpChainingStrategy is ILpStrategy {
  error StrategyDelegateCallFailed();

  enum ChainingInstructionType {
    Batch,
    DecreaseAndBatch
  }

  struct ChainingInstruction {
    InstructionType instructionType;
    address strategy;
    bytes params;
  }

  struct ModifiedAddonPrincipalAmountParams {
    uint256 addonPrincipalAmount;
    bytes params;
  }
}
