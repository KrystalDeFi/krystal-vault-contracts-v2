// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, DAI, AERODROME_NFPM as NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICLFactory } from "../../contracts/common/interfaces/protocols/aerodrome/ICLFactory.sol";
import { INonfungiblePositionManager as INFPM } from
  "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

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
import { LpStrategy } from "../../contracts/public-vault/strategies/lpAerodrome/LpStrategy.sol";
import { LpValidator } from "../../contracts/public-vault/strategies/lpAerodrome/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

address constant WETH = 0x4200000000000000000000000000000000000006;
address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

contract IntegrationTest is TestCommon {
  ConfigManager public configManager;
  Vault public vaultImplementation;
  LpValidator public validator;
  LpStrategy public lpStrategy;

  VaultFactory public vaultFactory;
  Vault public vaultInstance;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 35_350_500);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 100 ether);
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
    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));

    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
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

  function test_cannotChangePrincipalToken() public {
    console.log("==== test_cannotChangePrincipalToken ====");

    // User cannot change the principal token of the Vault
    vm.expectRevert(ICommon.InvalidVaultConfig.selector);
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: DAI,
        supportedAddresses: new address[](0)
      }),
      0
    );
  }

  function test_allowDepositEmptyVault() public {
    console.log("==== test_allowDepositEmptyVault ====");

    // User can turn ON allow_deposit for his private vault
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      }),
      0
    );

    // User can turn ON allow_deposit ONLY ONCE
    vm.expectRevert(ICommon.InvalidVaultConfig.selector);
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      }),
      0
    );

    // User cannot Turn off allow_deposit once it's on
    vm.expectRevert(ICommon.InvalidVaultConfig.selector);
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      }),
      0
    );
  }

  function test_integration() public {
    console.log("==== test_deposit ====");
    console.log("==== User can deposit principal to mint shares ====");

    uint256 currentBlock = block.number;

    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();

    // Deposit to a empty vault
    IERC20(WETH).approve(address(vaultInstance), 0.5 ether);
    vaultInstance.deposit(0.5 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    assertEq(IERC20(vaultInstance).balanceOf(USER), 0.5 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 0.5 ether);
    assertEq(vaultAssets.length, 1);
    assertEq(vaultAssets[0].amount, 0.5 ether);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));

    // Deposit to a vault with only principal
    IERC20(WETH).approve(address(vaultInstance), 0.5 ether);
    vaultInstance.deposit(0.5 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    assertEq(IERC20(vaultInstance).balanceOf(USER), 1 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 1 ether);
    assertEq(vaultAssets.length, 1);
    assertEq(vaultAssets[0].amount, 1 ether);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));

    // Deposit to a vault with both principal and LPs
    // User can add liquidity from principal to a new LP position
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.7 ether);
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      tickSpacing: 100,
      tickLower: -887_200,
      tickUpper: 887_200,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });
    vm.roll(++currentBlock);
    vaultInstance.allocate(assets, lpStrategy, 0, abi.encode(instruction));

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 0.3 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));

    // Deposit to a vault with both principal and LPs
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);

    // Ratio between the assets remain unchanged
    vaultAssets = vaultInstance.getInventory();
    assertApproxEqRel(IERC20(vaultInstance).balanceOf(USER), 20_000 ether, TOLERANCE);
    assertApproxEqRel(IERC20(WETH).balanceOf(address(vaultInstance)), 0.6 ether, TOLERANCE);
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 0.6 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.4 ether, TOLERANCE);

    // Manage Private Vault (ALLOW_DEPOSIT = false, UNSET RANGE, TVL, LIST_POOL)
    console.log("==== test_managePrivateVault ====");

    {
      // User can add liquidity from principal to an existing LP position
      AssetLib.Asset[] memory incAssets = new AssetLib.Asset[](2);
      incAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.3 ether);
      incAssets[1] = vaultAssets[1];
      ILpStrategy.SwapAndIncreaseLiquidityParams memory incParams =
        ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
      ICommon.Instruction memory incInstruction = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndIncreaseLiquidity),
        params: abi.encode(incParams)
      });
      vm.roll(++currentBlock);
      vaultInstance.allocate(incAssets, lpStrategy, 0, abi.encode(incInstruction));
    }

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 300_031_328_579_983_889, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal, 1_699_973_374_782_247_590, TOLERANCE);

    {
      // User can remove liquidity from LP position to principal
      (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
      AssetLib.Asset[] memory decAssets = new AssetLib.Asset[](1);
      decAssets[0] = vaultAssets[1];
      ILpStrategy.DecreaseLiquidityAndSwapParams memory decParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
        liquidity: (liquidity * 3) / 17,
        amount0Min: 0,
        amount1Min: 0,
        principalAmountOutMin: 0,
        swapData: ""
      });
      ICommon.Instruction memory decInstruction = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
        params: abi.encode(decParams)
      });
      vm.roll(++currentBlock);
      vaultInstance.allocate(decAssets, lpStrategy, 0, abi.encode(decInstruction));
    }

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 599_938_178_992_504_384, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal, 1_399_852_103_034_761_773, TOLERANCE);

    {
      // User can rebalance 1 specific LP
      AssetLib.Asset[] memory rebalanceAssets = new AssetLib.Asset[](1);
      rebalanceAssets[0] = vaultAssets[1];
      ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
        tickLower: -443_500,
        tickUpper: 443_500,
        decreasedAmount0Min: 0,
        decreasedAmount1Min: 0,
        amount0Min: 0,
        amount1Min: 0,
        compoundFee: true,
        compoundFeeAmountOutMin: 0,
        swapData: ""
      });
      ICommon.Instruction memory rebalanceInstruction = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndRebalancePosition),
        params: abi.encode(rebalanceParams)
      });
      vm.roll(++currentBlock);
      vaultInstance.allocate(rebalanceAssets, lpStrategy, 0, abi.encode(rebalanceInstruction));
    }

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 599_938_178_992_524_679, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal, 1_399_852_099_737_301_014, TOLERANCE);

    {
      // User can compound 1 specific LP
      AssetLib.Asset[] memory compoundAssets = new AssetLib.Asset[](1);
      compoundAssets[0] = vaultAssets[1];
      ILpStrategy.SwapAndCompoundParams memory compoundParams =
        ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
      ICommon.Instruction memory compoundInstruction = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndCompound),
        params: abi.encode(compoundParams)
      });
      vm.roll(++currentBlock);
      vaultInstance.allocate(compoundAssets, lpStrategy, 0, abi.encode(compoundInstruction));
    }

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 599_938_178_992_524_679, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal, 1_399_852_099_737_301_014, TOLERANCE);

    console.log("==== test_allowDepositVaultRevert ====");

    {
      // Existing assets should follow the vault config
      vm.expectRevert(ILpValidator.InvalidPool.selector);
      address[] memory newSupportedAddresses = new address[](1);
      newSupportedAddresses[0] = address(0);
      vaultInstance.allowDeposit(
        ICommon.VaultConfig({
          allowDeposit: true,
          rangeStrategyType: 0,
          tvlStrategyType: 0,
          principalToken: WETH,
          supportedAddresses: newSupportedAddresses
        }),
        0
      );
    }

    {
      // User can Allow Deposit with proper Vault Config
      // Existing assets should follow the vault config
      (,, address token0, address token1, int24 tickSpacing,,,,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
      address pool = ICLFactory(INFPM(NFPM).factory()).getPool(token0, token1, tickSpacing);
      address[] memory supportedAddresses = new address[](1);
      supportedAddresses[0] = pool;
      vaultInstance.allowDeposit(
        ICommon.VaultConfig({
          allowDeposit: true,
          rangeStrategyType: 0,
          tvlStrategyType: 0,
          principalToken: WETH,
          supportedAddresses: supportedAddresses
        }),
        0
      );
    }

    console.log("==== test_withdraw ====");
    console.log("==== User can burn shares to withdraw principals ====");
    console.log("==== Ratio between the assets should remain unchanged ====");
    console.log("==== Received principal tokens should match the diff of the Vault Value ====");

    vaultAssets = vaultInstance.getInventory();

    // Burn 0 share
    vm.expectRevert(IVault.InvalidShares.selector);
    vaultInstance.withdraw(0, false, 0);

    // Burn partial shares
    uint256 userVaultSharesBefore = vaultInstance.balanceOf(USER);
    vaultInstance.withdraw(0.5 ether * vaultInstance.SHARES_PRECISION(), false, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(
      userVaultSharesBefore - IERC20(vaultInstance).balanceOf(USER), 0.5 ether * vaultInstance.SHARES_PRECISION()
    );
    assertApproxEqRel(IERC20(WETH).balanceOf(address(vaultInstance)), 0.45 ether, TOLERANCE);
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 0.45 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.05 ether, TOLERANCE);

    // Burn all shares
    vaultInstance.withdraw(IERC20(vaultInstance).balanceOf(USER), false, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 0);
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 0);
    assertEq(vaultAssets.length, 0);

    // Test re-deposit to zero vault
    IERC20(WETH).approve(address(vaultInstance), 2 ether);
    vaultInstance.deposit(2 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 2 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 2 ether);
    assertEq(vaultAssets.length, 1);
    assertEq(vaultAssets[0].amount, 2 ether);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));

    {
      // Manage Public Vault (allowed deposit)
      console.log("==== test_managePublicVault ====");

      ILpValidator.LpStrategyConfig memory newConfig1 = ILpValidator.LpStrategyConfig({
        rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
        tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
      });

      newConfig1.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });

      newConfig1.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 10_000_000_000 ether });

      configManager.setStrategyConfig(address(validator), WETH, abi.encode(newConfig1));
    }

    {
      //  User can't add to a LP which the pool is smaller the the allowed TVL, at the time of adding
      AssetLib.Asset[] memory anotherAssets1 = new AssetLib.Asset[](1);
      anotherAssets1[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
      ILpStrategy.SwapAndMintPositionParams memory anotherParams1 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: WETH,
        token1: USDC,
        tickSpacing: 100,
        tickLower: -887_200,
        tickUpper: 887_200,
        amount0Min: 0,
        amount1Min: 0,
        swapData: ""
      });
      ICommon.Instruction memory anotherInstruction1 = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
        params: abi.encode(anotherParams1)
      });
      vm.roll(++currentBlock);
      vm.expectRevert(ILpValidator.InvalidPoolAmountMin.selector);
      vaultInstance.allocate(anotherAssets1, lpStrategy, 0, abi.encode(anotherInstruction1));
    }

    {
      //  User can't add/rebalance LP which is smaller than the allowed range
      //    Case non-stable
      ILpValidator.LpStrategyConfig memory newConfig2 = ILpValidator.LpStrategyConfig({
        rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
        tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
      });

      newConfig2.rangeConfigs[0] =
        ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 1_000_000, tickWidthTypedMin: 1_000_000 });

      newConfig2.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });

      configManager.setStrategyConfig(address(validator), WETH, abi.encode(newConfig2));
    }

    {
      AssetLib.Asset[] memory anotherAssets2 = new AssetLib.Asset[](1);
      anotherAssets2[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
      ILpStrategy.SwapAndMintPositionParams memory anotherParams2 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: WETH,
        token1: USDC,
        tickSpacing: 100,
        tickLower: -887_200,
        tickUpper: -884_200,
        amount0Min: 0,
        amount1Min: 0,
        swapData: ""
      });
      ICommon.Instruction memory anotherInstruction2 = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
        params: abi.encode(anotherParams2)
      });
      vm.roll(++currentBlock);
      vm.expectRevert(ILpValidator.InvalidTickWidth.selector);
      vaultInstance.allocate(anotherAssets2, lpStrategy, 0, abi.encode(anotherInstruction2));
    }

    {
      //  User can't add LP where the POOL_LIST is fixed and the pool is not in the POOL_LIST
      AssetLib.Asset[] memory anotherAssets3 = new AssetLib.Asset[](1);
      anotherAssets3[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
      ILpStrategy.SwapAndMintPositionParams memory anotherParams3 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: WETH,
        token1: USDC,
        tickSpacing: 200,
        tickLower: -887_200,
        tickUpper: -884_200,
        amount0Min: 0,
        amount1Min: 0,
        swapData: ""
      });
      ICommon.Instruction memory anotherInstruction3 = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
        params: abi.encode(anotherParams3)
      });
      vm.roll(++currentBlock);
      vm.expectRevert(ILpValidator.InvalidPool.selector);
      vaultInstance.allocate(anotherAssets3, lpStrategy, 0, abi.encode(anotherInstruction3));
    }
  }
}
