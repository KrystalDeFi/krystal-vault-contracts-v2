// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "../libraries/OptimalSwap.sol";

contract OptimalSwapLibTest {
  function isZeroForOneInRange(
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 sqrtPriceX96,
    uint256 sqrtRatioLowerX96,
    uint256 sqrtRatioUpperX96
  ) public pure returns (bool) {
    return OptimalSwap.isZeroForOne(amount0Desired, amount1Desired, sqrtPriceX96, sqrtRatioLowerX96, sqrtRatioUpperX96);
  }
}
