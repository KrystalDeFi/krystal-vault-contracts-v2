// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import "../ICommon.sol";

interface ILpValidator is ICommon {
  enum TokenType {
    Stable,
    Pegged
  }

  struct LpStrategyConfig {
    LpStrategyRangeConfig[] rangeConfigs;
    LpStrategyTvlConfig[] tvlConfigs;
  }

  struct LpStrategyRangeConfig {
    uint24 tickWidthMultiplierMin;
    uint24 tickWidthStableMultiplierMin;
  }

  struct LpStrategyTvlConfig {
    uint256 principalTokenAmountMin;
  }

  function validateConfig(
    INFPM nfpm,
    uint24 fee,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig calldata config
  ) external view;

  function validateTickWidth(
    INFPM nfpm,
    uint24 fee,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig calldata config
  ) external view;

  error InvalidPool();

  error InvalidPoolAmountAmountMin();

  error InvalidTickWidth();
}
