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
    vaultFactory = new VaultFactory(USER, WETH, address(configManager), address(vaultImplementation), USER, 1000);

    // User can create a Vault without any assets
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      ownerFeeBasisPoint: 1000,
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

    vaultInstance = Vault(vaultAddress);
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
    vaultInstance.allocate(assets, lpStrategy, abi.encode(instruction));

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
    assertEq(IERC20(vaultInstance).balanceOf(USER), 20_001_718_470_368_223_202_841);
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
    assertEq(valueOfPositionInPrincipal, 1_399_611_278_869_742_595);

    console.log("==== test_allowDepositVaultRevert ====");

    // Existing assets should follow the vault config
    vm.expectRevert(ILpStrategy.InvalidPool.selector);
    vaultInstance.allowDeposit(
      ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
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
    vaultInstance.withdraw(0);

    // Burn partial shares
    vaultInstance.withdraw(0.5 ether * vaultInstance.SHARES_PRECISION());
    vaultAssets = vaultInstance.getInventory();
    assertEq(
      IERC20(vaultInstance).balanceOf(USER),
      20_001_718_470_368_223_202_841 - 0.5 ether * vaultInstance.SHARES_PRECISION()
    );
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 450_051_554_441_936_792);
    assertEq(vaultAssets.length, 3);
    assertEq(vaultAssets[0].amount, 450_051_554_441_936_792);
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
    assertEq(valueOfPositionInPrincipal, 1_049_733_684_602_155_762);

    // Burn all shares
    vaultInstance.withdraw(IERC20(vaultInstance).balanceOf(USER));
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 0);
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 0);
    assertEq(vaultAssets.length, 3);
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
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertEq(valueOfPositionInPrincipal, 0);

    // Test re-deposit to zero vault
    IERC20(WETH).approve(address(vaultInstance), 2 ether);
    vaultInstance.deposit(2 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    assertEq(IERC20(vaultInstance).balanceOf(USER), 2 ether * vaultInstance.SHARES_PRECISION());
    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 2 ether);
    assertEq(vaultAssets.length, 3);
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
    valueOfPositionInPrincipal = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertEq(valueOfPositionInPrincipal, 0);
  }
}
