// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../../../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

import "../../ICommon.sol";

interface IAerodromeLpValidator is ICommon {
  struct LpStrategyConfig {
    LpStrategyRangeConfig[] rangeConfigs;
    LpStrategyTvlConfig[] tvlConfigs;
  }

  struct LpStrategyRangeConfig {
    int24 tickWidthMin;
    int24 tickWidthTypedMin;
  }

  struct LpStrategyTvlConfig {
    uint256 principalTokenAmountMin;
  }

  function validateConfig(
    INonfungiblePositionManager nfpm,
    int24 tickSpacing,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig calldata config
  ) external view;

  function validateTickWidth(
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig calldata config
  ) external view;

  function validateObservationCardinality(
    INonfungiblePositionManager nfpm,
    int24 tickSpacing,
    address token0,
    address token1
  ) external view;

  function validatePriceSanity(address pool) external view;

  function validateNfpm(address nfpm) external view;

  error InvalidPool();

  error InvalidNfpm();

  error InvalidPoolAmountMin();

  error InvalidTickWidth();

  error InvalidObservationCardinality();

  error InvalidObservation();

  error PriceSanityCheckFailed();
}
