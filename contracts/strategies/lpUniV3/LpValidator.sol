// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../../interfaces/strategies/ILpValidator.sol";
import "../../interfaces/strategies/ILpStrategy.sol";
import "../../interfaces/core/IConfigManager.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IPancakeV3Pool as IUniswapV3Pool } from "@pancakeswap/v3-core/contracts/interfaces/IPancakeV3Pool.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LpValidator is Ownable, ILpValidator {
  IConfigManager public configManager;
  mapping(address => bool) public whitelistNfpms;

  constructor(address _owner, address _configManager, address[] memory _whitelistNfpms) Ownable(_owner) {
    require(_configManager != address(0), ZeroAddress());

    configManager = IConfigManager(_configManager);
    for (uint256 i = 0; i < _whitelistNfpms.length; i++) {
      whitelistNfpms[_whitelistNfpms[i]] = true;
    }
  }

  function validateNfpm(address nfpm) external view {
    require(whitelistNfpms[address(nfpm)], InvalidNfpm());
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

    uint256 poolPrincipalTokenAmount = IERC20(config.principalToken).balanceOf(pool);

    // Check if the pool amount is greater than the minimum amount principal token
    require(poolPrincipalTokenAmount >= tvlConfig.principalTokenAmountMin, InvalidPoolAmountMin());

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

  function validateObservationCardinality(INFPM nfpm, uint24 fee, address token0, address token1) external view {
    address pool = IUniswapV3Factory(nfpm.factory()).getPool(token0, token1, fee);
    (,,, uint16 observationCardinality,,,) = IUniswapV3Pool(pool).slot0();
    require(observationCardinality >= 2, InvalidObservationCardinality());
  }

  /// @dev Check average price of the last 2 observed ticks compares to current tick
  /// @param pool The pool to check the price
  function validatePriceSanity(address pool) external view override {
    // get the observed price before this block
    unchecked {
      (, int24 tick, uint16 observationIndex, uint16 cardinality,,,) = IUniswapV3Pool(pool).slot0();
      require(cardinality > 0, InvalidObservationCardinality());
      uint32 lastTimestamp;
      int56 lastTickCummulative;
      uint32 secondLastTimestamp;
      int56 secondLastTickCummulative;
      bool initialized;
      (lastTimestamp, lastTickCummulative,, initialized) = IUniswapV3Pool(pool).observations(observationIndex);
      require(initialized, InvalidObservation());

      if (observationIndex == 0) observationIndex = cardinality - 1;
      else observationIndex--;
      (secondLastTimestamp, secondLastTickCummulative,, initialized) =
        IUniswapV3Pool(pool).observations(observationIndex);

      require(initialized, InvalidObservation());
      require(lastTimestamp > secondLastTimestamp, InvalidObservation());

      int24 lastTick =
        int24((lastTickCummulative - secondLastTickCummulative) / int32(lastTimestamp - secondLastTimestamp));
      require(
        -configManager.maxHarvestSlippage() < tick - lastTick && tick - lastTick < configManager.maxHarvestSlippage(),
        PriceSanityCheckFailed()
      ); // ~5%
    }
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

  function setWhitelistNfpms(address[] calldata _whitelistNfpms, bool isWhitelist) external onlyOwner {
    for (uint256 i; i < _whitelistNfpms.length; i++) {
      whitelistNfpms[_whitelistNfpms[i]] = isWhitelist;
    }
  }
}
