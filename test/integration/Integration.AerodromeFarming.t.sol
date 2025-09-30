// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, DAI, AERODROME_NFPM as NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ICLFactory } from "../../contracts/public-vault/interfaces/strategies/aerodrome/ICLFactory.sol";
import { INonfungiblePositionManager as INFPM } from
  "../../contracts/public-vault/interfaces/strategies/aerodrome/INonfungiblePositionManager.sol";
import { ICLGauge } from "../../contracts/public-vault/interfaces/strategies/aerodrome/ICLGauge.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/public-vault/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/public-vault/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { IVault } from "../../contracts/public-vault/interfaces/core/IVault.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { IAerodromeLpStrategy as ILpStrategy } from
  "../../contracts/public-vault/interfaces/strategies/aerodrome/IAerodromeLpStrategy.sol";
import { IAerodromeLpValidator as ILpValidator } from
  "../../contracts/public-vault/interfaces/strategies/aerodrome/IAerodromeLpValidator.sol";
import { IFarmingStrategy } from "../../contracts/public-vault/interfaces/strategies/aerodrome/IFarmingStrategy.sol";
import { LpStrategy } from "../../contracts/public-vault/strategies/lpAerodrome/LpStrategy.sol";
import { LpValidator } from "../../contracts/public-vault/strategies/lpAerodrome/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { FarmingStrategy } from "../../contracts/public-vault/strategies/lpAerodrome/FarmingStrategy.sol";
import { FarmingStrategyValidator } from
  "../../contracts/public-vault/strategies/lpAerodrome/FarmingStrategyValidator.sol";
import { RewardSwapper } from "../../contracts/public-vault/strategies/lpAerodrome/RewardSwapper.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";

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
  FarmingStrategyValidator public farmingValidator;
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

    // Set up FarmingStrategyValidator
    address[] memory initialFactories = new address[](1);
    // Get the gauge factory from the example gauge
    initialFactories[0] = ICLGauge(WETH_USDC_GAUGE).gaugeFactory();
    farmingValidator = new FarmingStrategyValidator(address(this), initialFactories);

    // Set up FarmingStrategy
    farmingStrategy = new FarmingStrategy(
      address(lpStrategy), address(configManager), address(rewardSwapper), address(farmingValidator)
    );

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

  function test_integration() public {
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
      IFarmingStrategy.CreateAndDepositLPParams memory params =
        IFarmingStrategy.CreateAndDepositLPParams({ gauge: WETH_USDC_GAUGE, lpParams: lpParams });

      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(IFarmingStrategy.FarmingInstructionType.CreateAndDepositLP),
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
      IFarmingStrategy.RebalanceAndDepositParams memory params = IFarmingStrategy.RebalanceAndDepositParams({
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
        instructionType: uint8(IFarmingStrategy.FarmingInstructionType.RebalanceAndDeposit),
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
      IFarmingStrategy.WithdrawLPToPrincipalParams memory params = IFarmingStrategy.WithdrawLPToPrincipalParams({
        decreaseAndSwapParams: ILpStrategy.DecreaseLiquidityAndSwapParams({
          liquidity: liquidity / 2,
          amount0Min: 0,
          amount1Min: 0,
          principalAmountOutMin: 0,
          swapData: ""
        })
      });
      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(IFarmingStrategy.FarmingInstructionType.WithdrawLPToPrincipal),
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
      IFarmingStrategy.WithdrawLPParams memory params = IFarmingStrategy.WithdrawLPParams({ minPrincipalAmount: 0 });

      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(IFarmingStrategy.FarmingInstructionType.WithdrawLP),
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
      IFarmingStrategy.DepositExistingLPParams memory params =
        IFarmingStrategy.DepositExistingLPParams({ gauge: WETH_USDC_GAUGE });

      ICommon.Instruction memory instruction = ICommon.Instruction({
        instructionType: uint8(IFarmingStrategy.FarmingInstructionType.DepositExistingLP),
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
}
