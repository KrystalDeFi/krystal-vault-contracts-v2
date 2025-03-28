// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";

contract IntegrationTest is TestCommon {
  ConfigManager public configManager;
  Vault public vaultImplementation;
  LpStrategy public lpStrategy;

  VaultFactory public vaultFactory;
  Vault public vaultInstance;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 100 ether);
    vm.deal(USER, 100 ether);

    // Set up ConfigManager
    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(ILpStrategy.TokenType.Stable);
    typedTokenTypes[1] = uint256(ILpStrategy.TokenType.Stable);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    lpStrategy = new LpStrategy(address(swapper), address(configManager));

    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(strategies, true);

    ILpStrategy.LpStrategyConfig memory initialConfig = ILpStrategy.LpStrategyConfig({
      rangeConfigs: new ILpStrategy.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpStrategy.LpStrategyTvlConfig[](1)
    });

    initialConfig.rangeConfigs[0] =
      ILpStrategy.LpStrategyRangeConfig({ tickWidthMultiplierMin: 3, tickWidthStableMultiplierMin: 3 });

    initialConfig.tvlConfigs[0] = ILpStrategy.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });

    configManager.setStrategyConfig(address(lpStrategy), WETH, abi.encode(initialConfig));

    // Set up VaultFactory
    vaultImplementation = new Vault();
    vaultFactory = new VaultFactory(USER, WETH, address(configManager), address(vaultImplementation));

    // User can create a Vault without any assets
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
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
      })
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
      })
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
      })
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
      })
    );
  }

  function test_integration() public {
    console.log("==== test_deposit ====");
    console.log("==== User can deposit principal to mint shares ====");

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
      fee: 500,
      tickLower: -887_220,
      tickUpper: 887_200,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });
    vaultInstance.allocate(assets, lpStrategy, 0, abi.encode(instruction));

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3);
    assertEq(vaultAssets[0].amount, 300_000_000_000_021_092);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));

    // Deposit to a vault with both principal and LPs
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);

    // Ratio between the assets remain unchanged
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 20_003_372_819_126_354_888_407);
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 600_051_554_552_220_855);
    assertEq(vaultAssets.length, 3);
    assertEq(vaultAssets[0].amount, 600_051_554_552_220_855);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertEq(valueOfPositionInPrincipal, 1_399_611_277_255_876_301);

    // Manage Private Vault (ALLOW_DEPOSIT = false, UNSET RANGE, TVL, LIST_POOL)
    console.log("==== test_managePrivateVault ====");

    // User can add liquidity from principal to an existing LP position
    AssetLib.Asset[] memory incAssets = new AssetLib.Asset[](2);
    incAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.3 ether);
    incAssets[1] = vaultAssets[2];
    ILpStrategy.SwapAndIncreaseLiquidityParams memory incParams =
      ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
    ICommon.Instruction memory incInstruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndIncreaseLiquidity),
      params: abi.encode(incParams)
    });
    vaultInstance.allocate(incAssets, lpStrategy, 0, abi.encode(incInstruction));

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3);
    assertEq(vaultAssets[0].amount, 300_051_554_699_492_528);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertEq(valueOfPositionInPrincipal, 1_699_542_383_158_745_664);

    // User can remove liquidity from LP position to principal
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[2].tokenId);
    AssetLib.Asset[] memory decAssets = new AssetLib.Asset[](1);
    decAssets[0] = vaultAssets[2];
    ILpStrategy.DecreaseLiquidityAndSwapParams memory decParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
      liquidity: liquidity * 3 / 17,
      amount0Min: 0,
      amount1Min: 0,
      principalAmountOutMin: 0,
      swapData: ""
    });
    ICommon.Instruction memory decInstruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      params: abi.encode(decParams)
    });
    vaultInstance.allocate(decAssets, lpStrategy, 0, abi.encode(decInstruction));

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3);
    assertEq(vaultAssets[0].amount, 599_895_229_166_993_117);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertEq(valueOfPositionInPrincipal, 1_399_617_609_667_000_197);

    // User can rebalance 1 specific LP
    AssetLib.Asset[] memory rebalanceAssets = new AssetLib.Asset[](1);
    rebalanceAssets[0] = vaultAssets[2];
    ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
      tickLower: -443_580,
      tickUpper: 443_580,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0,
      compoundFee: true,
      swapData: ""
    });
    ICommon.Instruction memory rebalanceInstruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndRebalancePosition),
      params: abi.encode(rebalanceParams)
    });
    vaultInstance.allocate(rebalanceAssets, lpStrategy, 0, abi.encode(rebalanceInstruction));

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 4);
    assertEq(vaultAssets[0].amount, 599_895_229_167_012_210);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 0);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertEq(valueOfPositionInPrincipal, 1_399_617_608_039_078_922);

    // User can compound 1 specific LP
    AssetLib.Asset[] memory compoundAssets = new AssetLib.Asset[](1);
    compoundAssets[0] = vaultAssets[3];
    ILpStrategy.SwapAndCompoundParams memory compoundParams =
      ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
    ICommon.Instruction memory compoundInstruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndCompound),
      params: abi.encode(compoundParams)
    });
    vaultInstance.allocate(compoundAssets, lpStrategy, 0, abi.encode(compoundInstruction));

    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 4);
    assertEq(vaultAssets[0].amount, 599_895_229_167_012_210);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 0);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertEq(valueOfPositionInPrincipal, 1_399_617_608_039_078_922);

    console.log("==== test_allowDepositVaultRevert ====");

    // Existing assets should follow the vault config
    vm.expectRevert(ILpStrategy.InvalidPool.selector);
    address[] memory newSupportedAddresses = new address[](1);
    newSupportedAddresses[0] = address(0);
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: newSupportedAddresses
      })
    );

    // User can Allow Deposit with proper Vault Config
    // Existing assets should follow the vault config
    (,, address token0, address token1, uint24 fee,,,,,,,) = INFPM(NFPM).positions(vaultAssets[2].tokenId);
    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(token0, token1, fee);
    address[] memory supportedAddresses = new address[](1);
    supportedAddresses[0] = pool;
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: supportedAddresses
      })
    );

    console.log("==== test_withdraw ====");
    console.log("==== User can burn shares to withdraw principals ====");
    console.log("==== Ratio between the assets should remain unchanged ====");
    console.log("==== Received principal tokens should match the diff of the Vault Value ====");

    vaultAssets = vaultInstance.getInventory();

    // Burn 0 share
    vm.expectRevert(IVault.InvalidShares.selector);
    vaultInstance.withdraw(0, false, 0);

    // Burn partial shares
    vaultInstance.withdraw(0.5 ether * vaultInstance.SHARES_PRECISION(), false, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(
      IERC20(vaultInstance).balanceOf(USER),
      20_003_372_819_126_354_888_407 - 0.5 ether * vaultInstance.SHARES_PRECISION()
    );
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 449_946_709_337_041_714);
    assertEq(vaultAssets.length, 4);
    assertEq(vaultAssets[0].amount, 449_946_709_337_041_714);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 0);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertEq(valueOfPositionInPrincipal, 1_049_767_369_166_682_815);

    // Burn all shares
    vaultInstance.withdraw(IERC20(vaultInstance).balanceOf(USER), false, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 0);
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 0);
    assertEq(vaultAssets.length, 4);
    assertEq(vaultAssets[0].amount, 0);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 0);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    assertEq(vaultAssets[3].amount, 0);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertEq(valueOfPositionInPrincipal, 0);

    // Test re-deposit to zero vault
    IERC20(WETH).approve(address(vaultInstance), 2 ether);
    vaultInstance.deposit(2 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 2 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 2 ether);
    assertEq(vaultAssets.length, 4);
    assertEq(vaultAssets[0].amount, 2 ether);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 0);
    assertEq(vaultAssets[1].token, USDC);
    assertEq(vaultAssets[1].tokenId, 0);
    assertEq(vaultAssets[1].strategy, address(0));
    assertEq(vaultAssets[2].amount, 0);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    assertEq(vaultAssets[3].amount, 0);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertEq(valueOfPositionInPrincipal, 0);

    // Manage Public Vault (allowed deposit)
    console.log("==== test_managePublicVault ====");

    ILpStrategy.LpStrategyConfig memory newConfig1 = ILpStrategy.LpStrategyConfig({
      rangeConfigs: new ILpStrategy.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpStrategy.LpStrategyTvlConfig[](1)
    });

    newConfig1.rangeConfigs[0] =
      ILpStrategy.LpStrategyRangeConfig({ tickWidthMultiplierMin: 3, tickWidthStableMultiplierMin: 3 });

    newConfig1.tvlConfigs[0] = ILpStrategy.LpStrategyTvlConfig({ principalTokenAmountMin: 10_000_000_000 ether });

    configManager.setStrategyConfig(address(lpStrategy), WETH, abi.encode(newConfig1));

    //  User can't add to a LP which the pool is smaller the the allowed TVL, at the time of adding

    AssetLib.Asset[] memory anotherAssets1 = new AssetLib.Asset[](1);
    anotherAssets1[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
    ILpStrategy.SwapAndMintPositionParams memory anotherParams1 = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
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
    vm.expectRevert(ILpStrategy.InvalidPoolAmountAmountMin.selector);
    vaultInstance.allocate(anotherAssets1, lpStrategy, 0, abi.encode(anotherInstruction1));

    //  User can't add/rebalance LP which is smaller than the allowed range
    //    Case non-stable

    ILpStrategy.LpStrategyConfig memory newConfig2 = ILpStrategy.LpStrategyConfig({
      rangeConfigs: new ILpStrategy.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpStrategy.LpStrategyTvlConfig[](1)
    });

    newConfig2.rangeConfigs[0] =
      ILpStrategy.LpStrategyRangeConfig({ tickWidthMultiplierMin: 1000, tickWidthStableMultiplierMin: 1000 });

    newConfig2.tvlConfigs[0] = ILpStrategy.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });

    configManager.setStrategyConfig(address(lpStrategy), WETH, abi.encode(newConfig2));

    AssetLib.Asset[] memory anotherAssets2 = new AssetLib.Asset[](1);
    anotherAssets2[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
    ILpStrategy.SwapAndMintPositionParams memory anotherParams2 = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
      tickLower: -887_220,
      tickUpper: -884_220,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory anotherInstruction2 = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(anotherParams2)
    });
    vm.expectRevert(ILpStrategy.InvalidTickWidth.selector);
    vaultInstance.allocate(anotherAssets2, lpStrategy, 0, abi.encode(anotherInstruction2));

    //  User can't add LP where the POOL_LIST is fixed and the pool is not in the POOL_LIST
    AssetLib.Asset[] memory anotherAssets3 = new AssetLib.Asset[](1);
    anotherAssets3[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
    ILpStrategy.SwapAndMintPositionParams memory anotherParams3 = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 100,
      tickLower: -887_220,
      tickUpper: -884_220,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory anotherInstruction3 = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(anotherParams3)
    });
    vm.expectRevert(ILpStrategy.InvalidPool.selector);
    vaultInstance.allocate(anotherAssets3, lpStrategy, 0, abi.encode(anotherInstruction3));
  }
}
