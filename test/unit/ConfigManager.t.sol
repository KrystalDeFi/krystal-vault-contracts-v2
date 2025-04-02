// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, DAI, USDC, NULL_ADDRESS } from "../TestCommon.t.sol";

import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";

contract ConfigManagerTest is TestCommon {
  ConfigManager public configManager;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);
  }

  function test_WhitelistStrategy() public {
    console.log("==== test_WhitelistStrategy ====");

    address[] memory whitelistStrategies = new address[](1);
    whitelistStrategies[0] = NULL_ADDRESS;

    configManager.whitelistStrategy(whitelistStrategies, true);

    assertTrue(configManager.isWhitelistedStrategy(NULL_ADDRESS));
    assertFalse(configManager.isWhitelistedStrategy(DAI));
  }

  function test_WhitelistSwapRouter() public {
    console.log("==== test_WhitelistSwapRouter ====");

    address[] memory whitelistSwapRouters = new address[](1);
    whitelistSwapRouters[0] = NULL_ADDRESS;

    configManager.whitelistSwapRouter(whitelistSwapRouters, true);

    assertTrue(configManager.isWhitelistedSwapRouter(NULL_ADDRESS));
    assertFalse(configManager.isWhitelistedSwapRouter(DAI));
  }

  function test_WhitelistAutomator() public {
    console.log("==== test_WhitelistAutomator ====");

    assertTrue(configManager.isWhitelistedAutomator(USER));
    assertFalse(configManager.isWhitelistedAutomator(DAI));

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = DAI;

    configManager.whitelistAutomator(whitelistAutomator, true);

    assertTrue(configManager.isWhitelistedAutomator(DAI));
    assertFalse(configManager.isWhitelistedAutomator(USDC));
  }

  function test_StableTokens() public {
    console.log("==== test_StableTokens ====");

    assertTrue(configManager.isMatchedWithType(DAI, uint256(1)));
    assertTrue(configManager.isMatchedWithType(USDC, uint256(1)));

    assertFalse(configManager.isMatchedWithType(NULL_ADDRESS, uint256(1)));

    address[] memory newStableTokens = new address[](1);
    newStableTokens[0] = DAI;

    uint256[] memory newStableTokenTypes = new uint256[](1);
    newStableTokenTypes[0] = uint256(1);

    configManager.setTypedTokens(newStableTokens, newStableTokenTypes);

    assertTrue(configManager.isMatchedWithType(DAI, uint256(1)));

    address[] memory newStableTokens2 = new address[](3);
    newStableTokens2[0] = DAI;
    newStableTokens2[1] = USDC;
    newStableTokens2[2] = NULL_ADDRESS;

    uint256[] memory newStableTokenTypes2 = new uint256[](3);
    newStableTokenTypes2[0] = uint256(1);
    newStableTokenTypes2[1] = uint256(1);
    newStableTokenTypes2[2] = uint256(1);

    configManager.setTypedTokens(newStableTokens2, newStableTokenTypes2);

    assertTrue(configManager.isMatchedWithType(DAI, uint256(1)));
    assertTrue(configManager.isMatchedWithType(USDC, uint256(1)));
    assertTrue(configManager.isMatchedWithType(NULL_ADDRESS, uint256(1)));
  }

  function test_StrategyConfigs() public {
    console.log("==== test_StrategyConfigs ====");

    ILpValidator.LpStrategyConfig memory lpStrategyConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
    });

    lpStrategyConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 200, tickWidthTypedMin: 300 });

    lpStrategyConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 100 });

    bytes memory config = abi.encode(lpStrategyConfig);

    configManager.setStrategyConfig(NULL_ADDRESS, DAI, config);

    bytes memory strategyConfig = configManager.getStrategyConfig(NULL_ADDRESS, DAI);

    ILpValidator.LpStrategyConfig memory lpStrategyConfig2 = abi.decode(strategyConfig, (ILpValidator.LpStrategyConfig));
    ILpValidator.LpStrategyRangeConfig memory rangeConfig = lpStrategyConfig2.rangeConfigs[0];
    ILpValidator.LpStrategyTvlConfig memory tvlConfig = lpStrategyConfig2.tvlConfigs[0];

    assertEq(tvlConfig.principalTokenAmountMin, 100);
    assertEq(rangeConfig.tickWidthMin, 200);
    assertEq(rangeConfig.tickWidthTypedMin, 300);
  }

  function test_MaxPositions() public {
    console.log("==== test_MaxPositions ====");

    assertEq(configManager.maxPositions(), 10);

    configManager.setMaxPositions(20);

    assertEq(configManager.maxPositions(), 20);
  }
}
