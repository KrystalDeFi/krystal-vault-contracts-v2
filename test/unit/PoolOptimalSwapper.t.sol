// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, IV3SwapRouter, WETH, DAI, USER, USDC, NFPM, PLATFORM_WALLET } from "../TestCommon.t.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { IOptimalSwapper } from "../../contracts/interfaces/core/IOptimalSwapper.sol";

contract PoolOptimalSwapperTest is TestCommon {
  function testOptimalSwap() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 28_399_917);
    vm.selectFork(fork);

    setErc20Balance(WETH, USER, 1000 ether);
    setErc20Balance(USDC, USER, 1000 ether);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    (uint256 amount0, uint256 amount1) = swapper.getOptimalSwapAmounts(
      0xd0b53D9277642d899DF5C87A3966A349A798F224, 498_947_572_268, 961, -201_500, -200_500, ""
    );
    (amount0, amount1) = swapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams(
        0xd0b53D9277642d899DF5C87A3966A349A798F224, 498_947_572_268, 961, -201_500, -200_500, ""
      )
    );
  }
}
