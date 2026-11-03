// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice The state of a Ramses CL pool the vault strategies value positions with. `slot0` has 7 fields with a
///         uint24 `feeProtocol` (FEE_DENOM 1e6) and `ticks` keeps Uniswap V3's 8-field layout, unlike Slipstream's.
interface IRamsesV3Pool {
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint24 feeProtocol,
      bool unlocked
    );

  function ticks(int24 tick)
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

  function feeGrowthGlobal0X128() external view returns (uint256);

  function feeGrowthGlobal1X128() external view returns (uint256);
}
