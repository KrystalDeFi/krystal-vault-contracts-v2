// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, IV3SwapRouter, WETH, DAI, USER, USDC, NFPM, PLATFORM_WALLET } from "../TestCommon.t.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { IOptimalSwapper } from "../../contracts/public-vault/interfaces/core/IOptimalSwapper.sol";
import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OptimalSwap } from "../../contracts/public-vault/libraries/OptimalSwap.sol";

contract PoolOptimalSwapperTest is TestCommon {
  function testOptimalSwap() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 1000 ether);
    setErc20Balance(USDC, USER, 1000 ether);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();

    IERC20(WETH).approve(address(swapper), 1000 ether);
    IERC20(USDC).approve(address(swapper), 1000 ether);
    (uint256 amount0After, uint256 amount1After) = swapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams(
        0xd0b53D9277642d899DF5C87A3966A349A798F224, 498_947_572_268, 961, -201_500, -200_500, ""
      )
    );
    assertLt(amount0After, 498_947_572_268);
    assertGt(amount1After, 961);

    console.log("==========");
    assertEq(
      false,
      OptimalSwap.isZeroForOne(
        0,
        808_401_318,
        3_951_727_649_479_010_892_136_946,
        3_851_966_005_701_440_317_093_773,
        4_049_450_403_053_124_526_823_087
      )
    );

    assertEq(
      true,
      OptimalSwap.isZeroForOne(
        808_401_318,
        0,
        3_951_727_649_479_010_892_136_946,
        3_851_966_005_701_440_317_093_773,
        4_049_450_403_053_124_526_823_087
      )
    );
  }
}
