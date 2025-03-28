// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, PLAYER_1, PLAYER_2, FLASHLOAN_PLAYER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";

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

  function print_vault_inventory() public view {
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    console.log("-----------------------------------------");
    for (uint256 i = 0; i < vaultAssets.length; i++) {
      console.log("asset %d token: %s", i, vaultAssets[i].token);
      console.log("asset %d amount: %s", i, vaultAssets[i].amount);
      console.log("asset %d tokenId: %s", i, vaultAssets[i].tokenId);
      console.log("asset %d strategy: %s", i, vaultAssets[i].strategy);      
      if (vaultAssets[i].strategy != address(0)) {
        console.log("asset %d strategy value: %s", i, ILpStrategy(vaultAssets[i].strategy).valueOf(vaultAssets[i], WETH));
      }
      console.log("weth balance of the vault: %s", IERC20(WETH).balanceOf(address(vaultInstance)));
    }
    console.log("Vault total value: %s", vaultInstance.getTotalValue());
    console.log("-----------------------------------------");
  }

  function setUp() public {
    console.log("Setting up the vault...");
    
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);    

    setErc20Balance(WETH, USER, 1 ether);
    setErc20Balance(WETH, PLAYER_1, 1 ether);
    setErc20Balance(WETH, PLAYER_2, 1 ether);
    setErc20Balance(WETH, FLASHLOAN_PLAYER, 300 ether);

    vm.deal(USER, 1 ether);

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
    console.log("strategies: ", address(strategies[0]));
    
    vm.startPrank(USER);
    configManager.whitelistStrategy(strategies, true);
    console.log("configManager.whitelistStrategy(strategies, true)");

    ILpStrategy.LpStrategyConfig memory initialConfig = ILpStrategy.LpStrategyConfig({
      rangeConfigs: new ILpStrategy.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpStrategy.LpStrategyTvlConfig[](1)
    });    

    initialConfig.rangeConfigs[0] =
      ILpStrategy.LpStrategyRangeConfig({ tickWidthMultiplierMin: 3, tickWidthStableMultiplierMin: 3 });

    initialConfig.tvlConfigs[0] = ILpStrategy.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });

    vm.startPrank(USER);
    configManager.setStrategyConfig(address(lpStrategy), WETH, abi.encode(initialConfig));
    console.log("configManager.setStrategyConfig(address(lpStrategy), WETH, abi.encode(initialConfig))");

    // Set up VaultFactory
    vaultImplementation = new Vault();
    vaultFactory = new VaultFactory(USER, WETH, address(configManager), address(vaultImplementation));

    console.log("vaultFactory: ", address(vaultFactory));
    // User can create a Vault without any assets
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      name: "Test Public Vault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    console.log("created params");

    vm.startPrank(USER);
    address vaultAddress = vaultFactory.createVault(params);
    console.log("created vault: ", vaultAddress);

    vaultInstance = Vault(payable(vaultAddress));
    console.log("vaultInstance: ", address(vaultInstance));
  }

  function test_cannotChangePrincipalToken() public {
    console.log("==== test_cannotChangePrincipalToken ====");

    // User cannot change the principal token of the Vault
    vm.startPrank(USER);
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
    console.log("Testing: User cannot Turn off allow_deposit once it's on");
    vm.startPrank(USER);
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

    print_vault_inventory();
    console.log("User is depositing 1 ether to an empty vault");
    vm.startPrank(USER);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vm.startPrank(USER);
    vaultInstance.deposit(1 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    print_vault_inventory();

    console.log("Player 1 is depositing 1 ether to the vault");
    vm.startPrank(PLAYER_1);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vm.startPrank(PLAYER_1);
    vaultInstance.deposit(1 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    print_vault_inventory();

    console.log("User is allocating 1 ether to a new LP position");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1.8 ether);
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
      tickLower: -287_220,
      tickUpper: -107_220,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });
    vm.startPrank(USER);
    vaultInstance.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    
    console.log("balance of the shares of the player 1: ", vaultInstance.balanceOf(PLAYER_1));
    console.log("weth balance of the player 1: ", IERC20(WETH).balanceOf(PLAYER_1));
    print_vault_inventory();

    console.log("FlashLoan is swapping 100 eth -> USDC");
    vm.startPrank(FLASHLOAN_PLAYER);
    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    IERC20(WETH).approve(address(swapper), IERC20(WETH).balanceOf(FLASHLOAN_PLAYER));
    console.log("Flashloan approved for 100 ether");
    (,, address token0, address token1, uint24 fee,,,,,,,) = INFPM(NFPM).positions(vaultInstance.getInventory()[2].tokenId);
    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(token0, token1, fee);
    console.log("pool: ", pool);    
    swapper.poolSwap(
      pool,
      250 ether,      
      WETH < USDC, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );

    console.log("FlashLoan is swapping eth -> USDC done");
    console.log("WETH balance of flashloan player: ", IERC20(WETH).balanceOf(FLASHLOAN_PLAYER));
    console.log("USDC balance of flashloan player: ", IERC20(USDC).balanceOf(FLASHLOAN_PLAYER));
    print_vault_inventory();

    // console.log("Player 1 is withdrawing more than the balance of the shares");    
    // vaultInstance.withdraw(vaultInstance.balanceOf(PLAYER_1) + 1, false);
    // vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, PLAYER_1, vaultInstance.balanceOf(PLAYER_1), vaultInstance.balanceOf(PLAYER_1) + 1));

    console.log("Player 1 is withdrawing a half from the vault");    
    vm.startPrank(PLAYER_1);
    vaultInstance.withdraw(vaultInstance.balanceOf(PLAYER_1) / 2, false, 0);
    // vaultInstance.withdraw(0.5 ether * vaultInstance.SHARES_PRECISION(), false);

    console.log("balance of the shares of the player 1: ", vaultInstance.balanceOf(PLAYER_1));
    console.log("weth balance of the player 1: ", IERC20(WETH).balanceOf(PLAYER_1));

    console.log("Player 1 is withdrawing the remaining half from the vault");
    vaultInstance.withdraw(vaultInstance.balanceOf(PLAYER_1), false, 0);

    console.log("balance of the shares of the player 1: ", vaultInstance.balanceOf(PLAYER_1));
    console.log("weth balance of the player 1: ", IERC20(WETH).balanceOf(PLAYER_1));

    print_vault_inventory();

    console.log("weth balance of the user: ", IERC20(WETH).balanceOf(USER));
    console.log("User is withdrawing all the shares");
    vm.startPrank(USER);
    vaultInstance.withdraw(vaultInstance.balanceOf(USER), false, 0);
    print_vault_inventory();
    console.log("weth balance of the user: ", IERC20(WETH).balanceOf(USER));
    console.log("usdc balance of the user: ", IERC20(USDC).balanceOf(USER));
    
  }

}
