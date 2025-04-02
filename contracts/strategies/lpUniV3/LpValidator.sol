// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../../interfaces/strategies/ILpValidator.sol";
import "../../interfaces/strategies/ILpStrategy.sol";
import "../../interfaces/core/IConfigManager.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

contract LpValidator is ILpValidator {
  IConfigManager public configManager;

  constructor(address _configManager) {
    require(_configManager != address(0), ZeroAddress());

    configManager = IConfigManager(_configManager);
  }

  /// @dev Checks the principal amount in the pool
  /// @param nfpm The non-fungible position manager
  /// @param fee The fee of the pool
  /// @param token0 The token0 of the pool
  /// @param token1 The token1 of the pool
  /// @param tickLower The lower tick of the position
  /// @param tickUpper The upper tick of the position
  /// @param config The configuration of the strategy
  function validateConfig(
    INFPM nfpm,
    uint24 fee,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig calldata config
  ) external view {
    LpStrategyConfig memory lpConfig =
      abi.decode(configManager.getStrategyConfig(address(this), config.principalToken), (LpStrategyConfig));

    LpStrategyRangeConfig memory rangeConfig = lpConfig.rangeConfigs[config.rangeStrategyType];
    LpStrategyTvlConfig memory tvlConfig = lpConfig.tvlConfigs[config.tvlStrategyType];

    address pool = IUniswapV3Factory(nfpm.factory()).getPool(token0, token1, fee);

    // Check if the pool is allowed
    require(_isPoolAllowed(config, pool), InvalidPool());

    (uint256 poolAmount0, uint256 poolAmount1) = _getAmountsForPool(IUniswapV3Pool(pool));

    // Check if the pool amount is greater than the minimum amount principal token
    require(
      (config.principalToken == token0 ? poolAmount0 : poolAmount1) >= tvlConfig.principalTokenAmountMin,
      InvalidPoolAmountMin()
    );

    // Check if tick width to mint/increase liquidity is greater than the minimum tick width
    uint256 token0Type = configManager.getTypedToken(token0);
    uint256 token1Type = configManager.getTypedToken(token1);

    int24 minTickWidth = token0Type == token1Type && token0Type > 0 && token1Type > 0
      ? rangeConfig.tickWidthTypedMin
      : rangeConfig.tickWidthMin;

    require(tickUpper - tickLower >= minTickWidth, InvalidTickWidth());
  }

  /// @dev Checks the tick width of the position
  /// @param token0 The token0 of the pool
  /// @param token1 The token1 of the pool
  /// @param tickLower The lower tick of the position
  /// @param tickUpper The upper tick of the position
  /// @param config The configuration of the strategy
  function validateTickWidth(
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig calldata config
  ) external view {
    LpStrategyConfig memory lpConfig =
      abi.decode(configManager.getStrategyConfig(address(this), config.principalToken), (LpStrategyConfig));

    LpStrategyRangeConfig memory rangeConfig = lpConfig.rangeConfigs[config.rangeStrategyType];

    // Check if tick width to mint/increase liquidity is greater than the minimum tick width
    uint256 token0Type = configManager.getTypedToken(token0);
    uint256 token1Type = configManager.getTypedToken(token1);

    int24 minTickWidth = token0Type == token1Type && token0Type > 0 && token1Type > 0
      ? rangeConfig.tickWidthTypedMin
      : rangeConfig.tickWidthMin;

    require(tickUpper - tickLower >= minTickWidth, InvalidTickWidth());
  }

  /// @dev Checks if the pool is allowed
  /// @param config The configuration of the strategy
  /// @param pool The pool to check
  /// @return allowed If the pool is allowed
  function _isPoolAllowed(VaultConfig memory config, address pool) internal pure returns (bool) {
    if (config.supportedAddresses.length == 0) return true;

    uint256 length = config.supportedAddresses.length;

    for (uint256 i; i < length;) {
      if (config.supportedAddresses[i] == pool) return true;

      unchecked {
        i++;
      }
    }

    return false;
  }

  /// @dev Gets the amounts for the pool
  /// @param pool IUniswapV3Pool
  /// @return amount0 The amount of token0
  /// @return amount1 The amount of token1
  function _getAmountsForPool(IUniswapV3Pool pool) internal view returns (uint256 amount0, uint256 amount1) {
    (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
    uint128 liquidity = pool.liquidity();
    (amount0, amount1) =
      LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO, liquidity);
  }
}
