// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER } from "../TestCommon.t.sol";

import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";

contract IntegrationTest is TestCommon {
  function setUp() public {
    vm.startBroadcast(USER);

    ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    initialConfig.rangeConfigs[1] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 1000, tickWidthTypedMin: 2 });
    initialConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4000, tickWidthTypedMin: 100 });

    initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    initialConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 5 });
    initialConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 50 });
    initialConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 500 });

    console.logBytes(abi.encode(initialConfig));
  }

  function test_config() public { }
}
