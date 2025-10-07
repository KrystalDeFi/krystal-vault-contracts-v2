// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICLFactory {
  function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}