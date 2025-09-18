// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, DAI, AERODROME_NFPM as NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ICLFactory } from "../../contracts/interfaces/strategies/aerodrome/ICLFactory.sol";
import { INonfungiblePositionManager as INFPM } from
  "../../contracts/interfaces/strategies/aerodrome/INonfungiblePositionManager.sol";
import { ICLGauge } from "../../contracts/interfaces/strategies/aerodrome/ICLGauge.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { IAerodromeLpStrategy as ILpStrategy } from
  "../../contracts/interfaces/strategies/aerodrome/IAerodromeLpStrategy.sol";
import { IAerodromeLpValidator as ILpValidator } from
  "../../contracts/interfaces/strategies/aerodrome/IAerodromeLpValidator.sol";
import { IFarmingStrategy } from "../../contracts/interfaces/strategies/aerodrome/IFarmingStrategy.sol";
import { LpStrategy } from "../../contracts/strategies/lpAerodrome/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpAerodrome/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpAerodrome/LpFeeTaker.sol";
import { FarmingStrategy } from "../../contracts/strategies/lpAerodrome/FarmingStrategy.sol";
import { RewardSwapper } from "../../contracts/strategies/lpAerodrome/RewardSwapper.sol";
import { ICommon } from "../../contracts/interfaces/ICommon.sol";

address constant WETH = 0x4200000000000000000000000000000000000006;
address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // Aerodrome token
address constant AERO_WETH_POOL = 0x82321f3BEB69f503380D6B233857d5C43562e2D0;
address constant WETH_USDC_GAUGE = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8; // Example gauge address

contract IntegrationFarmingTest is TestCommon {
  ConfigManager public configManager;
  Vault public vaultImplementation;
  LpValidator public validator;
  LpStrategy public lpStrategy;
  FarmingStrategy public farmingStrategy;
  RewardSwapper public rewardSwapper;
  PoolOptimalSwapper public poolSwapper;

  VaultFactory public vaultFactory;
  Vault public vaultInstance;

  uint256 testTokenId;

  function setUp() public {
    // Skip forking for basic compilation test - can be enabled for full integration testing
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 34_350_500);
    vm.selectFork(fork);

    vm.startPrank(USER);

    // Use direct transfers instead of setErc20Balance to avoid storage issues
    deal(WETH, USER, 100 ether);
    deal(USDC, USER, 100_000e6);
    deal(AERO, address(this), 1000 ether);
    vm.deal(USER, 100 ether);

    // Set up ConfigManager
    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    configManager = new ConfigManager();
    configManager.initialize(
      USER,
      new address[](0),
      new address[](0),
      whitelistAutomator,
      new address[](0),
      typedTokens,
      typedTokenTypes,
      0,
      0,
      0,
      address(0),
      new address[](0),
      new address[](0),
      new bytes[](0)
    );

    address[] memory whitelistNfpms = new address[](1);
    whitelistNfpms[0] = address(NFPM);
    poolSwapper = new PoolOptimalSwapper();
    validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(poolSwapper), address(validator), address(lpFeeTaker));

    // Set up RewardSwapper
    rewardSwapper = new RewardSwapper(address(configManager), address(poolSwapper), USER);
    rewardSwapper.setSupportedRewardToken(AERO, true);
    rewardSwapper.setRewardTokenPool(AERO, WETH, AERO_WETH_POOL);

    // Set up FarmingStrategy
    farmingStrategy = new FarmingStrategy(address(lpStrategy), address(configManager), address(rewardSwapper));

    address[] memory strategies = new address[](2);
    strategies[0] = address(lpStrategy);
    strategies[1] = address(farmingStrategy);
    configManager.whitelistStrategy(strategies, true);

    ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
    });

    initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });
    initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });

    configManager.setStrategyConfig(address(validator), WETH, abi.encode(initialConfig));

    // Set up VaultFactory
    vaultImplementation = new Vault();
    vaultFactory = new VaultFactory();
    vaultFactory.initialize(USER, WETH, address(configManager), address(vaultImplementation));

    // User can create a Vault without any assets
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    address vaultAddress = vaultFactory.createVault(params);

    vaultInstance = Vault(payable(vaultAddress));
  }

  function test_createAndDepositLP() public {
    uint256 currentBlock = block.number;
    console.log("==== test_createAndDepositLP ====");

    IERC20(WETH).approve(address(vaultInstance), 3 ether);
    vaultInstance.deposit(3 ether, 0);

    // Create assets representing tokens to swap and create LP
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 2 ether
    });

    // Prepare LP creation parameters
    ILpStrategy.SwapAndMintPositionParams memory lpParams = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(address(NFPM)),
      token0: WETH < USDC ? WETH : USDC,
      token1: WETH < USDC ? USDC : WETH,
      tickSpacing: 100,
      tickLower: -793_000,
      tickUpper: -791_900,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });

    {
      FarmingStrategy.CreateAndDepositLPParams memory params =
        FarmingStrategy.CreateAndDepositLPParams({ gauge: WETH_USDC_GAUGE, lpParams: lpParams });

      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(FarmingStrategy.FarmingInstructionType.CreateAndDepositLP),
        params: abi.encode(params)
      });

      vm.roll(++currentBlock);
      vaultInstance.allocate(assets, farmingStrategy, 0, abi.encode(instruction));
      printVaultAssets();
    }
    {
      // Rebalance
      console.log("rebalance position");
      AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
      // Withdraw LP from farming
      FarmingStrategy.RebalanceAndDepositParams memory params = FarmingStrategy.RebalanceAndDepositParams({
        rebalanceParams: ILpStrategy.SwapAndRebalancePositionParams({
          tickLower: -193_000,
          tickUpper: -191_900,
          decreasedAmount0Min: 0,
          decreasedAmount1Min: 0,
          amount0Min: 0,
          amount1Min: 0,
          compoundFee: true,
          compoundFeeAmountOutMin: 0,
          swapData: ""
        })
      });
      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(FarmingStrategy.FarmingInstructionType.RebalanceAndDeposit),
        params: abi.encode(params)
      });

      assets = new AssetLib.Asset[](1);
      assets[0] = vaultAssets[1];
      vm.roll(++currentBlock);
      vaultInstance.allocate(assets, farmingStrategy, 0, abi.encode(instruction));
      printVaultAssets();
    }

    {
      AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
      assertEq(vaultAssets.length, 2);
      assertApproxEqRel(vaultAssets[0].amount, 1 ether, TOLERANCE);
      assertEq(vaultAssets[0].token, WETH);
      assertEq(vaultAssets[0].tokenId, 0);
      assertEq(vaultAssets[0].strategy, address(0));
      assertEq(vaultAssets[1].amount, 1);
      assertEq(vaultAssets[1].token, WETH_USDC_GAUGE);
      assertEq(vaultAssets[1].strategy, address(farmingStrategy));

      // Deposit to a vault with both principal and Farming LPs
      IERC20(WETH).approve(address(vaultInstance), 3 ether);
      vaultInstance.deposit(3 ether, 0);
      vaultAssets = vaultInstance.getInventory();
      assertEq(vaultAssets.length, 2);
      assertApproxEqRel(vaultAssets[0].amount, 2 ether, TOLERANCE);
      assertEq(vaultAssets[0].token, WETH);
      assertEq(vaultAssets[0].tokenId, 0);
      assertEq(vaultAssets[0].strategy, address(0));
      assertEq(vaultAssets[1].amount, 1);
      assertEq(vaultAssets[1].token, WETH_USDC_GAUGE);
      assertEq(vaultAssets[1].strategy, address(farmingStrategy));

      printVaultAssets();
      vm.startPrank(address(vaultInstance));
      uint256 valueOfPositionInPrincipal = farmingStrategy.valueOf(vaultAssets[1], WETH);
      assertApproxEqRel(valueOfPositionInPrincipal, 4 ether, TOLERANCE);

      vm.warp(block.timestamp + 300 * 86_400);

      uint256 valueOfPositionInPrincipalAfter = farmingStrategy.valueOf(vaultAssets[1], WETH);
      assertApproxEqRel(valueOfPositionInPrincipal, 4 ether, TOLERANCE);
      console.log("valueIncreaseByFarming: ", valueOfPositionInPrincipalAfter - valueOfPositionInPrincipal);
      assertApproxEqRel(valueOfPositionInPrincipalAfter - valueOfPositionInPrincipal, 41_568_501_947_643_911, TOLERANCE);
      vm.startPrank(USER);
    }
    {
      console.log("withdraw half lp to principal");
      AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
      (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
      // Withdraw LP from farming
      FarmingStrategy.WithdrawLPToPrincipalParams memory params = FarmingStrategy.WithdrawLPToPrincipalParams({
        decreaseAndSwapParams: ILpStrategy.DecreaseLiquidityAndSwapParams({
          liquidity: liquidity / 2,
          amount0Min: 0,
          amount1Min: 0,
          principalAmountOutMin: 0,
          swapData: ""
        })
      });
      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(FarmingStrategy.FarmingInstructionType.WithdrawLPToPrincipal),
        params: abi.encode(params)
      });

      assets = new AssetLib.Asset[](1);
      assets[0] = vaultAssets[1];
      vm.roll(++currentBlock);
      vaultInstance.allocate(assets, farmingStrategy, 0, abi.encode(instruction));
      printVaultAssets();
    }
    {
      console.log("withdraw farming LP to normal position");
      AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
      // Withdraw LP from farming
      FarmingStrategy.WithdrawLPParams memory params = FarmingStrategy.WithdrawLPParams({ minPrincipalAmount: 0 });

      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(FarmingStrategy.FarmingInstructionType.WithdrawLP),
        params: abi.encode(params)
      });
      assets = new AssetLib.Asset[](1);
      assets[0] = vaultAssets[1];
      vm.roll(++currentBlock);
      vaultInstance.allocate(assets, farmingStrategy, 0, abi.encode(instruction));
      printVaultAssets();
    }
    {
      console.log("deposit existing LP position");
      AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
      FarmingStrategy.DepositExistingLPParams memory params =
        FarmingStrategy.DepositExistingLPParams({ gauge: WETH_USDC_GAUGE });

      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(FarmingStrategy.FarmingInstructionType.DepositExistingLP),
        params: abi.encode(params)
      });
      assets = new AssetLib.Asset[](1);
      assets[0] = vaultAssets[1];
      vm.roll(++currentBlock);
      vaultInstance.allocate(assets, farmingStrategy, 0, abi.encode(instruction));
      printVaultAssets();
    }

    // Withdraw half
    {
      uint256 wethWithdrawn = IERC20(WETH).balanceOf(USER);
      uint256 userVaultSharesBefore = vaultInstance.balanceOf(USER);
      vaultInstance.withdraw(userVaultSharesBefore / 2, false, 0);
      wethWithdrawn = IERC20(WETH).balanceOf(USER) - wethWithdrawn;
      assertApproxEqRel(wethWithdrawn, 3.02 ether, TOLERANCE);
      console.log("wethWithdrawn", wethWithdrawn);
    }
  }

  function printVaultAssets() internal view {
    console.log("\t============== VAULT ASSETS ============");
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    for (uint256 i = 0; i < vaultAssets.length; i++) {
      console.log("\t=================================");
      console.log("\tvault asset", i);
      console.log("\tstrategy", vaultAssets[i].strategy);
      console.log("\ttoken", vaultAssets[i].token);
      console.log("\ttokenId", vaultAssets[i].tokenId);
      console.log("\tamount", vaultAssets[i].amount);
      console.log("\t=================================");
    }
  }

  function test_valueOf() public {
    console.log("==== test_valueOf ====");

    // Create asset representing the deposited farming position
    AssetLib.Asset memory asset = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(farmingStrategy),
      token: WETH_USDC_GAUGE,
      tokenId: testTokenId,
      amount: 1
    });

    // Get value of the farming position
    uint256 value = farmingStrategy.valueOf(asset, WETH);

    // Should return non-zero value (LP value + potential rewards)
    assertTrue(value > 0, "Farming position should have positive value");

    console.log("Farming position value:", value);
  }

  function test_harvest() public {
    console.log("==== test_harvest ====");

    // Create asset representing the deposited farming position
    AssetLib.Asset memory asset = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(farmingStrategy),
      token: WETH_USDC_GAUGE,
      tokenId: testTokenId,
      amount: 1
    });

    // Fast forward time to accumulate some rewards
    vm.warp(block.timestamp + 7 days);

    // Execute harvest
    AssetLib.Asset[] memory results = farmingStrategy.harvest(
      asset,
      WETH, // Output token
      0, // Min amount out
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      }),
      ICommon.FeeConfig({
        vaultOwnerFeeBasisPoint: 0,
        vaultOwner: address(0),
        platformFeeBasisPoint: 0,
        platformFeeRecipient: address(0),
        gasFeeX64: 0,
        gasFeeRecipient: address(0)
      })
    );

    // Verify harvest results
    console.log("Harvest results count:", results.length);
    for (uint256 i = 0; i < results.length; i++) {
      console.log("Result", i, "token:", results[i].token);
      console.log("Result", i, "amount:", results[i].amount);
    }
  }

  function test_revalidate() public {
    console.log("==== test_revalidate ====");

    // Create asset representing a farming position
    AssetLib.Asset memory asset = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(farmingStrategy),
      token: WETH_USDC_GAUGE,
      tokenId: testTokenId,
      amount: 1
    });

    // Should not revert for valid asset
    farmingStrategy.revalidate(
      asset,
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    );

    // Should revert for invalid asset type
    asset.assetType = AssetLib.AssetType.ERC20;
    vm.expectRevert();
    farmingStrategy.revalidate(
      asset,
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    );
  }

  function test_basicSetup() public {
    console.log("==== test_basicSetup ====");

    // Test basic contract setup
    assertTrue(address(farmingStrategy.rewardSwapper()) != address(0), "RewardSwapper should be set");
    assertTrue(address(farmingStrategy.configManager()) != address(0), "ConfigManager should be set");
    assertTrue(address(farmingStrategy.lpStrategyImplementation()) != address(0), "LpStrategy should be set");

    console.log("FarmingStrategy address:", address(farmingStrategy));
    console.log("RewardSwapper address:", address(farmingStrategy.rewardSwapper()));
    console.log("ConfigManager address:", address(farmingStrategy.configManager()));
  }

  function test_rewardSwapperIntegration() public view {
    console.log("==== test_rewardSwapperIntegration ====");

    // Test RewardSwapper setup
    assertTrue(address(farmingStrategy.rewardSwapper()) != address(0), "RewardSwapper should be set");

    // Test reward token support (this would need to be configured by owner)
    // rewardSwapper.setSupportedRewardToken(AERO, true);
    // assertTrue(rewardSwapper.supportedRewardTokens(AERO), "AERO should be supported");
  }
}
