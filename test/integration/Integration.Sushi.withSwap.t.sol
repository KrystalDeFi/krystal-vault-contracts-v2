// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, PLAYER_1, PLAYER_2, BIGHAND_PLAYER, WETH, DAI, USDC, SUSHI_NFPM } from "../TestCommon.t.sol";

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
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";

contract IntegrationTest is TestCommon {
  ConfigManager public configManager;
  Vault public vaultImplementation;
  LpStrategy public lpStrategy;

  VaultFactory public vaultFactory;
  Vault public vaultInstance;

  uint256 public swap_amount;

  function setUp() public {
    console.log("Setting up the vault...");

    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    setErc20Balance(WETH, USER, 1 ether);
    setErc20Balance(WETH, PLAYER_1, 1 ether);
    setErc20Balance(WETH, PLAYER_2, 1 ether);
    setErc20Balance(WETH, BIGHAND_PLAYER, 3.58 ether);
    swap_amount = 70_000_000_000;
    setErc20Balance(USDC, BIGHAND_PLAYER, swap_amount);

    vm.deal(USER, 1 ether);

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
    whitelistNfpms[0] = address(SUSHI_NFPM);
    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    LpValidator validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(swapper), address(validator), address(lpFeeTaker));

    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
    console.log("strategies: ", address(strategies[0]));

    vm.startPrank(USER);
    configManager.whitelistStrategy(strategies, true);
    console.log("configManager.whitelistStrategy(strategies, true)");

    ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
      rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
      tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
    });

    initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });

    initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });

    vm.startPrank(USER);
    configManager.setStrategyConfig(address(validator), WETH, abi.encode(initialConfig));
    console.log("configManager.setStrategyConfig(address(validator), WETH, abi.encode(initialConfig))");

    // Set up VaultFactory
    vaultImplementation = new Vault();
    vaultFactory = new VaultFactory();
    vaultFactory.initialize(USER, WETH, address(configManager), address(vaultImplementation));

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

    vm.startPrank(USER);
    address vaultAddress = vaultFactory.createVault(params);
    console.log("created vault: ", vaultAddress);

    vaultInstance = Vault(payable(vaultAddress));
    console.log("vaultInstance: ", address(vaultInstance));
  }

  function test_sushi() public {
    // uint256 p1_old_weth_balance = IERC20(WETH).balanceOf(PLAYER_1);
    // uint256 user_old_weth_balance = IERC20(WETH).balanceOf(USER);

    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();

    console.log("==== Owner is depositing 1 ether to an empty vault ====");
    vm.startPrank(USER);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    console.log("==== Owner is allocating 1 ether to a new LP position ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.95 ether);
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(SUSHI_NFPM),
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
    vm.roll(block.number + 1);
    vaultInstance.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    assertEq(vaultInstance.balanceOf(USER), 10_000_000_000_000_000_000_000);

    console.log("==== Player 1 is depositing 1 ether to the vault ====");
    vm.startPrank(PLAYER_1);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);
    vaultAssets = vaultInstance.getInventory();

    console.log("++ share balance of the player: %s", vaultInstance.balanceOf(PLAYER_1));

    uint256 totalSupply = vaultInstance.totalSupply();
    uint256 balanceOfPlayer1 = vaultInstance.balanceOf(PLAYER_1);
    uint256 balanceOfUser = vaultInstance.balanceOf(USER);

    assert(balanceOfPlayer1 * 205 >= totalSupply * 100);
    assert(balanceOfPlayer1 * 195 <= totalSupply * 100);
    assert(balanceOfUser * 205 >= totalSupply * 100);
    assert(balanceOfUser * 195 <= totalSupply * 100);

    console.log("++ share balance of the owner: ", vaultInstance.balanceOf(USER));
    console.log("++ total value of the vault (before the swap): ", vaultInstance.getTotalValue());

    (,, address token0, address token1, uint24 fee,,,,,,,) =
      INFPM(SUSHI_NFPM).positions(vaultInstance.getInventory()[1].tokenId);
    address pool = IUniswapV3Factory(INFPM(SUSHI_NFPM).factory()).getPool(token0, token1, fee);
    console.log("++ pool address: ", pool);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();

    console.log("----------------------------- Starting a new round of swap");
    console.log("==== bighand is swapping all USDC -> wETH ====");
    vm.startPrank(BIGHAND_PLAYER);
    IERC20(USDC).approve(address(swapper), IERC20(USDC).balanceOf(BIGHAND_PLAYER));
    swapper.poolSwap(
      pool,
      IERC20(USDC).balanceOf(BIGHAND_PLAYER),
      WETH > USDC, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );

    console.log("==== bighand is swapping all wETH -> USDC ====");
    vm.startPrank(BIGHAND_PLAYER);
    IERC20(WETH).approve(address(swapper), IERC20(WETH).balanceOf(BIGHAND_PLAYER));
    swapper.poolSwap(
      pool,
      IERC20(WETH).balanceOf(BIGHAND_PLAYER),
      WETH < USDC, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );

    console.log("----------------------------- Ended a round of swap");
    console.log("USDC balance of bighand player: ", IERC20(USDC).balanceOf(BIGHAND_PLAYER));

    console.log("==== Player 1 is withdrawing all from the vault ====");
    vm.startPrank(PLAYER_1);
    vaultInstance.withdraw(vaultInstance.balanceOf(PLAYER_1), false, 0);
    assertEq(vaultInstance.balanceOf(PLAYER_1), 0, "PLAYER_1 balance of vault should be 0");

    vm.startPrank(USER);
    console.log("==== user is withdrawing all the shares ====");
    vaultInstance.withdraw(vaultInstance.balanceOf(USER), false, 0);
    assertEq(vaultInstance.balanceOf(USER), 0, "USER balance of vault should be 0");

    assertEq(IERC20(WETH).balanceOf(address(vaultInstance)), 0, "WETH balance of vault should be 0");
    assertEq(IERC20(USDC).balanceOf(address(vaultInstance)), 0, "USDC balance of vault should be 0");

    assertEq(vaultInstance.getTotalValue(), 0, "Total value of the vault should be 0");
    // assertGt(IERC20(WETH).balanceOf(USER), IERC20(WETH).balanceOf(PLAYER_1), "User balance should > player_1
    // balance");

    // the WETH balance of players shouldn't be too much different with the initial balance
    assert(0.99 ether < IERC20(WETH).balanceOf(USER));
    assert(IERC20(WETH).balanceOf(USER) < 1.01 ether);
    assert(0.99 ether < IERC20(WETH).balanceOf(PLAYER_1));
    assert(IERC20(WETH).balanceOf(PLAYER_1) < 1.01 ether);

    console.log(">>> Summary of case: swapping %d USDC -> wETH <<<", swap_amount / (10 ** 6));
    console.log(">>> WETH balance of user: ", IERC20(WETH).balanceOf(USER));
    console.log(">>> WETH balance of player 1: ", IERC20(WETH).balanceOf(PLAYER_1));
  }
}
