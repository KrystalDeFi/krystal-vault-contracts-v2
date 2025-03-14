// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, DAI, USDC, NULL_ADDRESS } from "../TestCommon.t.sol";

import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";

contract ConfigManagerTest is TestCommon {
  ConfigManager public configManager;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    address[] memory stableTokens = new address[](2);
    stableTokens[0] = DAI;
    stableTokens[1] = USDC;
    configManager = new ConfigManager(stableTokens);
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

  function test_StableTokens() public {
    console.log("==== test_StableTokens ====");

    address[] memory stableTokens = new address[](2);
    stableTokens[0] = configManager.stableTokens(0);
    stableTokens[1] = configManager.stableTokens(1);

    assertEq(stableTokens[0], DAI);
    assertEq(stableTokens[1], USDC);

    assertFalse(configManager.isStableToken(NULL_ADDRESS));

    address[] memory newStableTokens = new address[](1);
    newStableTokens[0] = DAI;

    configManager.setStableTokens(newStableTokens);

    address[] memory stableTokens2 = new address[](1);
    stableTokens2[0] = configManager.stableTokens(0);

    assertEq(stableTokens2[0], DAI);
    assertTrue(configManager.isStableToken(DAI));
    assertFalse(configManager.isStableToken(USDC));

    address[] memory newStableTokens2 = new address[](3);
    newStableTokens2[0] = DAI;
    newStableTokens2[1] = USDC;
    newStableTokens2[2] = NULL_ADDRESS;

    configManager.setStableTokens(newStableTokens2);

    address[] memory stableTokens3 = new address[](3);
    stableTokens3[0] = configManager.stableTokens(0);
    stableTokens3[1] = configManager.stableTokens(1);
    stableTokens3[2] = configManager.stableTokens(2);

    assertEq(stableTokens3[0], DAI);
    assertEq(stableTokens3[1], USDC);
    assertEq(stableTokens3[2], NULL_ADDRESS);
    assertTrue(configManager.isStableToken(DAI));
    assertTrue(configManager.isStableToken(USDC));
    assertTrue(configManager.isStableToken(NULL_ADDRESS));
  }

  function test_StrategyConfigs() public {
    console.log("==== test_StrategyConfigs ====");

    ILpStrategy.LpStrategyConfig memory lpStrategyConfig = ILpStrategy.LpStrategyConfig({
      principalTokenAmountMin: 100,
      tickWidthMultiplierMin: 200,
      tickWidthStableMultiplierMin: 300
    });

    bytes memory config = abi.encode(lpStrategyConfig);

    configManager.setStrategyConfig(NULL_ADDRESS, DAI, 1, config);

    bytes memory strategyConfig = configManager.getStrategyConfig(NULL_ADDRESS, DAI, 1);

    ILpStrategy.LpStrategyConfig memory lpStrategyConfig2 = abi.decode(strategyConfig, (ILpStrategy.LpStrategyConfig));

    assertEq(lpStrategyConfig2.principalTokenAmountMin, 100);
    assertEq(lpStrategyConfig2.tickWidthMultiplierMin, 200);
    assertEq(lpStrategyConfig2.tickWidthStableMultiplierMin, 300);
  }

  function test_MaxPositions() public {
    console.log("==== test_MaxPositions ====");

    assertEq(configManager.maxPositions(), 10);

    configManager.setMaxPositions(20);

    assertEq(configManager.maxPositions(), 20);
  }
}
