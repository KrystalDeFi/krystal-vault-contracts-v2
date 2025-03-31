// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, PLAYER_1, PLAYER_2, BIGHAND_PLAYER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";

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
    console.log("Setting up the vault...");
    
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);    

    setErc20Balance(WETH, USER, 1 ether);
    setErc20Balance(WETH, PLAYER_1, 1 ether);
    setErc20Balance(WETH, PLAYER_2, 1 ether);
    setErc20Balance(WETH, BIGHAND_PLAYER, 0 ether);
    setErc20Balance(USDC, BIGHAND_PLAYER, 100_000_000_000);

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
    // Owner can create a Vault without any assets
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

    // Owner cannot change the principal token of the Vault
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
    console.log("Testing: Owner cannot Turn off allow_deposit once it's on");
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
    

    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    
    console.log("==== Owner is depositing 1 ether to an empty vault ====");
    vm.startPrank(USER);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    console.log("usdc balance of the owner (before depositing): ", IERC20(USDC).balanceOf(USER));
    vaultInstance.deposit(1 ether, 0);
    vaultAssets = vaultInstance.getInventory();
    
    console.log("==== Owner is allocating 1 ether to a new LP position ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.95 ether);
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

 
    assertEq(vaultInstance.balanceOf(USER), 10000000000000000000000);    

    console.log("==== bighand is swapping 100_000 USDC -> wETH ====");
    vm.startPrank(BIGHAND_PLAYER);
    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    IERC20(USDC).approve(address(swapper), IERC20(USDC).balanceOf(BIGHAND_PLAYER)); console.log("bighand approved for USDC");
    (,, address token0, address token1, uint24 fee,,,,,,,) = INFPM(NFPM).positions(vaultInstance.getInventory()[2].tokenId);
    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(token0, token1, fee);
    console.log("pool: ", pool);    
    swapper.poolSwap(
      pool,
      100_000_000_000,      
      WETH > USDC, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );
    console.log("bighand is swapping 100_000 USDC -> wETH done");    
    console.log("WETH balance of bighand player: ", IERC20(WETH).balanceOf(BIGHAND_PLAYER));
    console.log("USDC balance of bighand player: ", IERC20(USDC).balanceOf(BIGHAND_PLAYER));

    uint256 p1_old_weth_balance = IERC20(WETH).balanceOf(PLAYER_1);

    console.log("==== Player 1 is depositing 1 ether to the vault ====");
    vm.startPrank(PLAYER_1);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    console.log("balance of the shares of the player 1: ", vaultInstance.balanceOf(PLAYER_1));
    console.log("balance of the shares of the owner: ", vaultInstance.balanceOf(USER));
    
    assert(vaultInstance.balanceOf(PLAYER_1) > vaultInstance.balanceOf(USER));

    console.log("==== bighand is swapping all wETH -> USDC ====");
    vm.startPrank(BIGHAND_PLAYER);    
    IERC20(WETH).approve(address(swapper), IERC20(WETH).balanceOf(BIGHAND_PLAYER)); console.log("bighand approved for wETH");
    swapper.poolSwap(
      IUniswapV3Factory(INFPM(NFPM).factory()).getPool(token0, token1, fee),
      IERC20(WETH).balanceOf(BIGHAND_PLAYER),
      WETH < USDC, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );

    console.log("WETH balance of bighand player: ", IERC20(WETH).balanceOf(BIGHAND_PLAYER));
    console.log("USDC balance of bighand player: ", IERC20(USDC).balanceOf(BIGHAND_PLAYER));
    

    console.log("balance of the shares of the player 1: ", vaultInstance.balanceOf(PLAYER_1));
    console.log("weth balance of the player 1: ", IERC20(WETH).balanceOf(PLAYER_1));

    console.log("==== Player 1 is withdrawing all from the vault ====");
    vm.startPrank(PLAYER_1);
    vaultInstance.withdraw(vaultInstance.balanceOf(PLAYER_1), false, 0);

    console.log("balance of the shares of the player 1: ", vaultInstance.balanceOf(PLAYER_1));
    console.log("weth balance of the player 1: ", IERC20(WETH).balanceOf(PLAYER_1));

    uint256 dollar_gain_player_1 = (IERC20(WETH).balanceOf(PLAYER_1) - p1_old_weth_balance) * 2000 / (10 ** 12);  // given the ETH price is 2000
    uint256 dollar_loss_bighand_player = 100_000_000_000 - IERC20(USDC).balanceOf(BIGHAND_PLAYER);

    console.log(">>> weth gain of the player 1: ", IERC20(WETH).balanceOf(PLAYER_1) - p1_old_weth_balance);
    console.log(">>> gain of the player 1 in dollars: ", dollar_gain_player_1);
    console.log(">>> loss of the bighand player in USDC: ", 100_000_000_000 - IERC20(USDC).balanceOf(BIGHAND_PLAYER));

    assert(IERC20(WETH).balanceOf(PLAYER_1) > p1_old_weth_balance);
    assert(dollar_gain_player_1 < dollar_loss_bighand_player);

    console.log("weth balance of the owner: ", IERC20(WETH).balanceOf(USER));
    console.log("==== Owner is withdrawing all the shares ====");
    console.log("usdc balance of the owner: ", IERC20(USDC).balanceOf(USER));

    vm.startPrank(USER);
    console.log("==== user is withdrawing all the shares ====");
    vaultInstance.withdraw(vaultInstance.balanceOf(USER), false, 0);

    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 0);
    assertEq(IERC20(USDC).balanceOf(address(vaultInstance)), 0);
    assertEq(vaultInstance.balanceOf(USER), 0);
    assertEq(vaultInstance.balanceOf(PLAYER_1), 0);    
    
    console.log("weth balance of the owner: ", IERC20(WETH).balanceOf(USER));
    console.log("usdc balance of the owner: ", IERC20(USDC).balanceOf(USER));
    
  }

}
