// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3Pool {
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint32 feeProtocol,
      bool unlocked
    );

  function positions(bytes32 _positionId)
    external
    view
    returns (
      uint128 liquidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    );

  function feeGrowthGlobal0X128() external view returns (uint256);
  function feeGrowthGlobal1X128() external view returns (uint256);

  function ticks(int24 _tick)
    external
    view
    returns (
      uint128 liquidityGross,
      int128 liquidityNet,
      uint256 feeGrowthOutside0X128,
      uint256 feeGrowthOutside1X128,
      int56 tickCumulativeOutside,
      uint160 secondsPerLiquidityOutsideX128,
      uint32 secondsOutside,
      bool initialized
    );
}

interface IKodiakIsland {
  // User functions
  function mint(uint256 mintAmount, address receiver)
    external
    returns (uint256 amount0, uint256 amount1, uint128 liquidityMinted);

  function burn(uint256 burnAmount, address receiver)
    external
    returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);

  function getUnderlyingBalancesAtPrice(uint160 sqrtRatioX96)
    external
    view
    returns (uint256 amount0Current, uint256 amount1Current);
  function manager() external view returns (address);

  function getMintAmounts(uint256 amount0Max, uint256 amount1Max)
    external
    view
    returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function getUnderlyingBalances() external view returns (uint256 amount0, uint256 amount1);

  function getPositionID() external view returns (bytes32 positionID);

  function token0() external view returns (IERC20);

  function token1() external view returns (IERC20);

  function upperTick() external view returns (int24);

  function lowerTick() external view returns (int24);

  function pool() external view returns (IUniswapV3Pool);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function managerFeeBPS() external view returns (uint16);

  function islandFactory() external view returns (address);
}
