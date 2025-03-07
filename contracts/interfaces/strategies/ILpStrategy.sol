// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IStrategy.sol";

import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface ILpStrategy is IStrategy {
  enum InstructionType {
    MintPosition,
    IncreaseLiquidity,
    DecreaseLiquidity
  }

  struct Instruction {
    InstructionType instructionType;
    bytes params;
  }

  struct MintPositionParams {
    INFPM nfpm;
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct IncreaseLiquidityParams {
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct DecreaseLiquidityParams {
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
  }

  function initialize(address _principalToken) external;
}
