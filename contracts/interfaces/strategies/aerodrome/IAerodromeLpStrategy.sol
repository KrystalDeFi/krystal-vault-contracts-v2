// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../IStrategy.sol";

import "./INonfungiblePositionManager.sol";

interface IAerodromeLpStrategy is IStrategy {
  enum InstructionType {
    // MintPosition,
    SwapAndMintPosition,
    // IncreaseLiquidity,
    SwapAndIncreaseLiquidity,
    DecreaseLiquidityAndSwap,
    SwapAndRebalancePosition,
    SwapAndCompound
  }

  event LpStrategyCompound(
    address vaultAddress, uint256 amount0Collected, uint256 amount1Collected, AssetLib.Asset[] compoundAssets
  );

  struct MintPositionParams {
    INonfungiblePositionManager nfpm;
    address token0;
    address token1;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Min;
    uint256 amount1Min;
  }

  struct SwapAndMintPositionParams {
    INonfungiblePositionManager nfpm;
    address token0;
    address token1;
    int24 tickSpacing;
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

  struct SwapAndRebalancePositionParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 decreasedAmount0Min;
    uint256 decreasedAmount1Min;
    uint256 amount0Min;
    uint256 amount1Min;
    bool compoundFee;
    uint256 compoundFeeAmountOutMin;
    bytes swapData;
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
}
