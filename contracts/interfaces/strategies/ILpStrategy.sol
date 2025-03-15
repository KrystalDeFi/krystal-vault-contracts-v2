// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IStrategy.sol";

import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface ILpStrategy is IStrategy {
  enum InstructionType {
    MintPosition,
    SwapAndMintPosition,
    IncreaseLiquidity,
    SwapAndIncreaseLiquidity,
    DecreaseLiquidity,
    DecreaseLiquidityAndSwap,
    RebalancePosition,
    SwapAndRebalancePosition,
    Compound,
    SwapAndCompound
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

  struct SwapAndMintPositionParams {
    INFPM nfpm;
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Min;
    uint256 amount1Min;
    bytes swapData;
  }

  struct IncreaseLiquidityParams {
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct SwapAndIncreaseLiquidityParams {
    uint256 amount0Min;
    uint256 amount1Min;
    bytes swapData;
  }

  struct DecreaseLiquidityParams {
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct DecreaseLiquidityAndSwapParams {
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 principalAmountOutMin;
    bytes swapData;
  }

  struct RebalancePositionParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 decreasedAmount0Min;
    uint256 decreasedAmount1Min;
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct SwapAndRebalancePositionParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 decreasedAmount0Min;
    uint256 decreasedAmount1Min;
    uint256 amount0Min;
    uint256 amount1Min;
    bytes swapData;
  }

  struct CompoundParams {
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct SwapAndCompoundParams {
    uint256 amount0Min;
    uint256 amount1Min;
    bytes swapData;
  }

  struct SwapFromPrincipalParams {
    uint256 principalTokenAmount;
    address pool;
    address principalToken;
    address otherToken;
    int24 tickLower;
    int24 tickUpper;
    bytes swapData;
  }

  struct SwapToPrincipalParams {
    address pool;
    address principalToken;
    address token;
    uint256 amount;
    uint256 amountOutMin;
    bytes swapData;
  }

  struct LpStrategyConfig {
    uint256 principalTokenAmountMin;
    uint24 tickWidthMultiplierMin;
    uint24 tickWidthStableMultiplierMin;
  }

  error InvalidPool();

  error InvalidPoolAmountAmountMin();

  error InvalidTickWidth();
}
