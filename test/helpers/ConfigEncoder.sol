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
    nativeConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 100 });

    nativeConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    nativeConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 5 ether });
    nativeConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 50 ether });
    nativeConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 500 ether });

    console.log("==== nativeConfig ====");
    console.logBytes(abi.encode(nativeConfig));

    ILpValidator.LpStrategyConfig memory stableConfigWith6Decimals = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    stableConfigWith6Decimals.rangeConfigs[0] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    stableConfigWith6Decimals.rangeConfigs[1] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 2 });
    // ~50% and 1% wide
    stableConfigWith6Decimals.rangeConfigs[2] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 100 });

    stableConfigWith6Decimals.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    stableConfigWith6Decimals.tvlConfigs[1] =
      ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 10_000 * 10 ** 6 });
    stableConfigWith6Decimals.tvlConfigs[2] =
      ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 100_000 * 10 ** 6 });
    stableConfigWith6Decimals.tvlConfigs[3] =
      ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 1_000_000 * 10 ** 6 });

    console.log("==== stableConfigWith6Decimals ====");
    console.logBytes(abi.encode(stableConfigWith6Decimals));

    ILpValidator.LpStrategyConfig memory stableConfigWith18Decimals = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    stableConfigWith18Decimals.rangeConfigs[0] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    stableConfigWith18Decimals.rangeConfigs[1] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 2 });
    // ~50% and 1% wide
    stableConfigWith18Decimals.rangeConfigs[2] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 100 });

    stableConfigWith18Decimals.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    stableConfigWith18Decimals.tvlConfigs[1] =
      ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 10_000 ether });
    stableConfigWith18Decimals.tvlConfigs[2] =
      ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 100_000 ether });
    stableConfigWith18Decimals.tvlConfigs[3] =
      ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 1_000_000 ether });

    console.log("==== stableConfigWith18Decimals ====");
    console.logBytes(abi.encode(stableConfigWith18Decimals));
  }

  function test_config() public { }
}
