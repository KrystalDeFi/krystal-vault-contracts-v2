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
    nativeConfig.rangeConfigs[1] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 0 });
    // ~50% and 1% wide
    nativeConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 0 });

    nativeConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    nativeConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 4 ether });
    nativeConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 40 ether });
    nativeConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 400 ether });

    console.log("==== nativeConfig ====");
    console.logBytes(abi.encode(nativeConfig));

    ILpValidator.LpStrategyConfig memory btcConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    btcConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    btcConfig.rangeConfigs[1] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 0 });
    // ~50% and 1% wide
    btcConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 0 });

    btcConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    btcConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 * 10 ** 8 });
    btcConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 1 * 10 ** 8 });
    btcConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 10 * 10 ** 8 });

    console.log("==== btcConfig ====");
    console.logBytes(abi.encode(btcConfig));

    ILpValidator.LpStrategyConfig memory hypeConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    hypeConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    hypeConfig.rangeConfigs[1] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 0 });
    // ~50% and 1% wide
    hypeConfig.rangeConfigs[2] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 0 });

    hypeConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 });
    hypeConfig.tvlConfigs[1] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 180 ether });
    hypeConfig.tvlConfigs[2] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 1800 ether });
    hypeConfig.tvlConfigs[3] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 18_000 ether });

    console.log("==== hypeConfig ====");
    console.logBytes(abi.encode(hypeConfig));

    ILpValidator.LpStrategyConfig memory stableConfigWith6Decimals = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](3),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](4)
    });

    stableConfigWith6Decimals.rangeConfigs[0] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 0, tickWidthTypedMin: 0 });
    // ~10% and 0.02% wide
    stableConfigWith6Decimals.rangeConfigs[1] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 0 });
    // ~50% and 1% wide
    stableConfigWith6Decimals.rangeConfigs[2] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 0 });

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
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 953, tickWidthTypedMin: 0 });
    // ~50% and 1% wide
    stableConfigWith18Decimals.rangeConfigs[2] =
      ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 4055, tickWidthTypedMin: 0 });

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

  function test_config() public pure {
    // decode the config
    ILpValidator.LpStrategyConfig memory config = abi.decode(
      bytes(
        hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b900000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000fd7000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000016345785d8a00000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000008ac7230489e80000"
      ),
      (ILpValidator.LpStrategyConfig)
    );

    console.log("==== decoded nativeConfig ====");
    for (uint256 i = 0; i < config.rangeConfigs.length; i++) {
      console.log("rangeConfigs[", i, "]: ");
      console.log("- tickWidthMin", config.rangeConfigs[i].tickWidthMin);
      console.log("- tickWidthTypedMin", config.rangeConfigs[i].tickWidthTypedMin);
    }
    for (uint256 i = 0; i < config.tvlConfigs.length; i++) {
      console.log("tvlConfigs[", i, "]: ", config.tvlConfigs[i].principalTokenAmountMin);
    }
  }
}
