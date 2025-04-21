// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IFeeTaker } from "./IFeeTaker.sol";
import { ICommon } from "../ICommon.sol";

interface ILpFeeTaker is IFeeTaker, ICommon {
  function takeFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    FeeConfig memory feeConfig,
    address principalToken,
    address pool,
    address validator
  ) external returns (uint256 fee0, uint256 fee1);
}
