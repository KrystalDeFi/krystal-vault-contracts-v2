// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { KatanaPoolOptimalSwapper } from "../../contracts/strategies/roninKatanaV3/KatanaPoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { KatanaLpFeeTaker } from "../../contracts/strategies/roninKatanaV3/KatanaLpFeeTaker.sol";

contract IntegrationTest is TestCommon {
  address constant NFPM = 0x7cF0fb64d72b733695d77d197c664e90D07cF45A;
  address constant USDC = 0x0B7007c13325C48911F73A2daD5FA5dCBf808aDc;
  address constant RON = 0xe514d9DEB7966c8BE0ca922de8a064264eA6bcd4;

  ConfigManager public configManager;
  Vault public vaultImplementation;
  LpValidator public validator;
  LpStrategy public lpStrategy;

  VaultFactory public vaultFactory;
  Vault public vaultInstance;

  function setUp() public {
    uint256 fork = vm.createFork("https://ronin.drpc.org/", 45_264_950);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(RON, USER, 100 ether);
    vm.deal(USER, 100 ether);

    // Set up ConfigManager
    address[] memory typedTokens = new address[](2);
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
    // AggregateRouter
    KatanaPoolOptimalSwapper swapper = new KatanaPoolOptimalSwapper(0x5F0aCDD3eC767514fF1BF7e79949640bf94576BD);
    validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    // AggregateRouter
    KatanaLpFeeTaker lpFeeTaker = new KatanaLpFeeTaker(0x5F0aCDD3eC767514fF1BF7e79949640bf94576BD);
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

    configManager.setStrategyConfig(address(validator), RON, abi.encode(initialConfig));

    // Set up VaultFactory
    vaultImplementation = new Vault();
    vaultFactory = new VaultFactory();
    vaultFactory.initialize(USER, RON, address(configManager), address(vaultImplementation));

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
        principalToken: RON,
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
        principalToken: USDC,
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
        principalToken: RON,
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
        principalToken: RON,
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
        principalToken: RON,
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
    IERC20(RON).approve(address(vaultInstance), 0.5 ether);
    vaultInstance.deposit(0.5 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    assertEq(IERC20(vaultInstance).balanceOf(USER), 0.5 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(RON).balanceOf(address(vaultInstance)), 0.5 ether);
    assertEq(vaultAssets.length, 1);
    assertEq(vaultAssets[0].amount, 0.5 ether);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));

    // Deposit to a vault with only principal
    IERC20(RON).approve(address(vaultInstance), 0.5 ether);
    vaultInstance.deposit(0.5 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    assertEq(IERC20(vaultInstance).balanceOf(USER), 1 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(RON).balanceOf(address(vaultInstance)), 1 ether);
    assertEq(vaultAssets.length, 1);
    assertEq(vaultAssets[0].amount, 1 ether);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));

    // Deposit to a vault with both principal and LPs
    // User can add liquidity from principal to a new LP position
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), RON, 0, 0.7 ether);
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: USDC,
      token1: RON,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
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
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));

    // Deposit to a vault with both principal and LPs
    IERC20(RON).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);

    // Ratio between the assets remain unchanged
    vaultAssets = vaultInstance.getInventory();
    assertApproxEqRel(IERC20(vaultInstance).balanceOf(USER), 20_000 ether, TOLERANCE);
    assertApproxEqRel(IERC20(RON).balanceOf(address(vaultInstance)), 0.6 ether, TOLERANCE);
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 0.6 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], RON);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.4 ether, TOLERANCE);

    // Manage Private Vault (ALLOW_DEPOSIT = false, UNSET RANGE, TVL, LIST_POOL)
    console.log("==== test_managePrivateVault ====");

    {
      // User can add liquidity from principal to an existing LP position
      AssetLib.Asset[] memory incAssets = new AssetLib.Asset[](2);
      incAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), RON, 0, 0.3 ether);
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
    assertApproxEqRel(vaultAssets[0].amount, 0.3 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], RON);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.7 ether, TOLERANCE);

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
    assertApproxEqRel(vaultAssets[0].amount, 0.6 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], RON);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.4 ether, TOLERANCE);

    {
      // User can rebalance 1 specific LP
      AssetLib.Asset[] memory rebalanceAssets = new AssetLib.Asset[](1);
      rebalanceAssets[0] = vaultAssets[1];
      ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
        tickLower: -443_580,
        tickUpper: 443_580,
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
    assertApproxEqRel(vaultAssets[0].amount, 0.6 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], RON);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.4 ether, TOLERANCE);

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
    assertApproxEqRel(vaultAssets[0].amount, 0.6 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], RON);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.4 ether, TOLERANCE);

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
          principalToken: RON,
          supportedAddresses: newSupportedAddresses
        }),
        0
      );
    }

    {
      // User can Allow Deposit with proper Vault Config
      // Existing assets should follow the vault config
      (,, address token0, address token1, uint24 fee,,,,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
      address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(token0, token1, fee);
      address[] memory supportedAddresses = new address[](1);
      supportedAddresses[0] = pool;
      vaultInstance.allowDeposit(
        ICommon.VaultConfig({
          allowDeposit: true,
          rangeStrategyType: 0,
          tvlStrategyType: 0,
          principalToken: RON,
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

    uint256 userVaultSharesBefore = vaultInstance.balanceOf(USER);
    // Burn partial shares
    vaultInstance.withdraw(0.5 ether * vaultInstance.SHARES_PRECISION(), false, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(
      userVaultSharesBefore - IERC20(vaultInstance).balanceOf(USER), 0.5 ether * vaultInstance.SHARES_PRECISION()
    );
    assertApproxEqRel(IERC20(RON).balanceOf(address(vaultInstance)), 0.45 ether, TOLERANCE);
    assertEq(vaultAssets.length, 2);
    assertApproxEqRel(vaultAssets[0].amount, 0.45 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, RON);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[1], RON);
    assertApproxEqRel(valueOfPositionInPrincipal, 1.05 ether, TOLERANCE);

    // Burn all shares
    vaultInstance.withdraw(IERC20(vaultInstance).balanceOf(USER), false, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 0);
    assertEq(IERC20(RON).balanceOf(address(vaultInstance)), 0);
    assertEq(vaultAssets.length, 0);

    // Test re-deposit to zero vault
    IERC20(RON).approve(address(vaultInstance), 2 ether);
    vaultInstance.deposit(2 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 2 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(RON).balanceOf(address(vaultInstance)), 2 ether);
    assertEq(vaultAssets.length, 1);
    assertEq(vaultAssets[0].amount, 2 ether);
    assertEq(vaultAssets[0].token, RON);
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

      configManager.setStrategyConfig(address(validator), RON, abi.encode(newConfig1));
    }

    {
      //  User can't add to a LP which the pool is smaller the the allowed TVL, at the time of adding
      AssetLib.Asset[] memory anotherAssets1 = new AssetLib.Asset[](1);
      anotherAssets1[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), RON, 0, 0.1 ether);
      ILpStrategy.SwapAndMintPositionParams memory anotherParams1 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: USDC,
        token1: RON,
        fee: 3000,
        tickLower: -887_220,
        tickUpper: 887_220,
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

      configManager.setStrategyConfig(address(validator), RON, abi.encode(newConfig2));
    }

    {
      AssetLib.Asset[] memory anotherAssets2 = new AssetLib.Asset[](1);
      anotherAssets2[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), RON, 0, 0.1 ether);
      ILpStrategy.SwapAndMintPositionParams memory anotherParams2 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: USDC,
        token1: RON,
        fee: 3000,
        tickLower: -887_220,
        tickUpper: -887_160,
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
      anotherAssets3[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), RON, 0, 0.1 ether);
      ILpStrategy.SwapAndMintPositionParams memory anotherParams3 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: USDC,
        token1: RON,
        fee: 500,
        tickLower: -887_220,
        tickUpper: 887_220,
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
      anotherParams3 = ILpStrategy.SwapAndMintPositionParams({
        nfpm: INFPM(NFPM),
        token0: USDC,
        token1: RON,
        fee: 3000,
        tickLower: -887_220,
        tickUpper: 887_220,
        amount0Min: 0,
        amount1Min: 0,
        swapData: ""
      });
      anotherInstruction3 = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
        params: abi.encode(anotherParams3)
      });
      vaultInstance.allocate(anotherAssets3, lpStrategy, 0, abi.encode(anotherInstruction3));
    }

    {
      vaultAssets = vaultInstance.getInventory();
      // User can decrease all liquidity from a LP position to principal
      (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
      AssetLib.Asset[] memory decAssets = new AssetLib.Asset[](1);
      decAssets[0] = vaultAssets[1];
      ILpStrategy.DecreaseLiquidityAndSwapParams memory decParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
        liquidity: liquidity,
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
      vaultAssets = vaultInstance.getInventory();
      assertEq(vaultAssets.length, 1);
    }

    {
      // User can withdraw all principal tokens
      vaultInstance.withdraw(IERC20(vaultInstance).balanceOf(USER), false, 0);
      vaultAssets = vaultInstance.getInventory();
      assertEq(IERC20(vaultInstance).balanceOf(USER), 0);
      assertEq(IERC20(RON).balanceOf(address(vaultInstance)), 0);
      assertEq(vaultAssets.length, 0);
    }
  }
}
