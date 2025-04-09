// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER } from "../TestCommon.t.sol";

import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";

contract IntegrationTest is TestCommon {
  function setUp() public {
    vm.startBroadcast(USER);

    ILpValidator.LpStrategyConfig memory nativeConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    nativeConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    nativeConfig.rangeConfigs[1] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 2 });
    // ~50% and 1% wide
    nativeConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4054, tickWidthTypedMin: 99 });

    nativeConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    nativeConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 5 });
    nativeConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 50 });
    nativeConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 500 });

    console.log("==== nativeConfig ====");
    console.logBytes(abi.encode(nativeConfig));

    ILpValidator.LpStrategyConfig memory stableConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    stableConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    stableConfig.rangeConfigs[1] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 2 });
    // ~50% and 1% wide
    stableConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4054, tickWidthTypedMin: 99 });

    stableConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    stableConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 10_000 });
    stableConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 100_000 });
    stableConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 1_000_000 });

    console.log("==== stableConfig ====");
    console.logBytes(abi.encode(stableConfig));
  }

  function test_config() public { }
}
