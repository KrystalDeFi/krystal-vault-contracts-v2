// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, PLAYER_1, PLAYER_2, BIGHAND_PLAYER, WETH, USDC, MORPHO, NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/public-vault/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/public-vault/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { IVault } from "../../contracts/public-vault/interfaces/core/IVault.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/public-vault/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/public-vault/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/public-vault/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/public-vault/interfaces/strategies/ILpValidator.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

contract IntegrationTest is TestCommon {
  ConfigManager public configManager;
  Vault public vaultImplementation;
  LpStrategy public lpStrategy;

  VaultFactory public vaultFactory;
  Vault public vaultInstance;

  uint256 public init_weth_balance_for_bighand_player;
  uint256 public init_2nd_token_balance_for_bighand_player;

  function setUp() public {
    console.log("Setting up the vault...");

    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    setErc20Balance(WETH, USER, 1 ether);
    setErc20Balance(WETH, PLAYER_1, 1 ether);
    setErc20Balance(WETH, PLAYER_2, 1 ether);
    init_weth_balance_for_bighand_player = 0 ether;
    setErc20Balance(WETH, BIGHAND_PLAYER, init_weth_balance_for_bighand_player);

    init_2nd_token_balance_for_bighand_player = 200_000 ether;
    setErc20Balance(MORPHO, BIGHAND_PLAYER, init_2nd_token_balance_for_bighand_player);

    vm.deal(USER, 1 ether);

    // Set up ConfigManager
    address[] memory typedTokens = new address[](2);
    typedTokens[0] = USDC;
    typedTokens[1] = MORPHO;

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

    console.log("the current maxHarvestSlippage", configManager.maxHarvestSlippage());

    address[] memory whitelistNfpms = new address[](1);
    whitelistNfpms[0] = address(NFPM);
    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    LpValidator validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));

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
      vaultOwnerFeeBasisPoint: 0,
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

  function test_uniswap_price_sanity_check_withdraw() public {
    // uint256 p1_old_weth_balance = IERC20(WETH).balanceOf(PLAYER_1);
    // uint256 user_old_weth_balance = IERC20(WETH).balanceOf(USER);

    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();

    console.log("==== Owner is depositing 1 ether to an empty vault ====");
    vm.startPrank(USER);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);
    vm.roll(block.number + 1);
    vaultAssets = vaultInstance.getInventory();

    console.log("==== Owner is allocating 1 ether to a new LP position ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.95 ether);
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: MORPHO,
      fee: 3000,
      tickLower: 72_540,
      tickUpper: 75_120,
      // tick spacing: 60
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
    vm.roll(block.number + 1);
    assertEq(vaultInstance.balanceOf(USER), 10_000_000_000_000_000_000_000);

    console.log("==== Player 1 is depositing 1 ether to the vault ====");
    vm.startPrank(PLAYER_1);
    IERC20(WETH).approve(address(vaultInstance), 1 ether);
    vaultInstance.deposit(1 ether, 0);
    vm.roll(block.number + 1);
    vaultAssets = vaultInstance.getInventory();

    uint256 totalSupply = vaultInstance.totalSupply();
    uint256 balanceOfPlayer1 = vaultInstance.balanceOf(PLAYER_1);
    uint256 balanceOfUser = vaultInstance.balanceOf(USER);

    assert(balanceOfPlayer1 * 205 >= totalSupply * 100);
    assert(balanceOfPlayer1 * 195 <= totalSupply * 100);
    assert(balanceOfUser * 205 >= totalSupply * 100);
    assert(balanceOfUser * 195 <= totalSupply * 100);

    (,, address token0, address token1, uint24 fee,,,,,,,) =
      INFPM(NFPM).positions(vaultInstance.getInventory()[2].tokenId);
    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(token0, token1, fee);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();

    console.log("==== (1) bighand is swapping %d MORPHO -> wETH ====", IERC20(MORPHO).balanceOf(BIGHAND_PLAYER));
    vm.startPrank(BIGHAND_PLAYER);
    IERC20(MORPHO).approve(address(swapper), IERC20(MORPHO).balanceOf(BIGHAND_PLAYER));
    swapper.poolSwap(
      pool,
      IERC20(MORPHO).balanceOf(BIGHAND_PLAYER),
      WETH > MORPHO, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );
    vm.roll(block.number + 1);

    console.log("==== Player 1 is withdrawing all from the vault (expect to be reverted) ====");
    vm.startPrank(PLAYER_1);
    uint256 vaultInstanceBalanceP1 = vaultInstance.balanceOf(PLAYER_1);
    vm.expectRevert(ILpValidator.PriceSanityCheckFailed.selector);

    vaultInstance.withdraw(vaultInstanceBalanceP1, false, 0);
    vm.roll(block.number + 1);

    console.log("==== User is setting maxHarvestSlippage to 1000% ====");
    vm.startPrank(USER);
    configManager.setMaxHarvestSlippage(100_000);
    vm.roll(block.number + 1);
    console.log("the current maxHarvestSlippage", configManager.maxHarvestSlippage());

    console.log("==== Player 1 is withdrawing all from the vault (again) ====");
    vm.startPrank(PLAYER_1);
    vaultInstance.withdraw(vaultInstance.balanceOf(PLAYER_1), false, 0);

    console.log("==== (2) bighand is paying back the loan by swapping all wETH -> MORPHO ====");
    vm.startPrank(BIGHAND_PLAYER);
    IERC20(WETH).approve(address(swapper), IERC20(WETH).balanceOf(BIGHAND_PLAYER));
    swapper.poolSwap(
      pool,
      IERC20(WETH).balanceOf(BIGHAND_PLAYER),
      WETH < MORPHO, // true if WETH is token0
      0, // amountOutMin - 0 for testing
      "" // empty data
    );

    if (init_2nd_token_balance_for_bighand_player > IERC20(MORPHO).balanceOf(BIGHAND_PLAYER)) {
      console.log("==== (3) bighand converts the lost to wETH to compare ====");
      uint256 weth_balance_before = IERC20(WETH).balanceOf(BIGHAND_PLAYER);
      vm.startPrank(BIGHAND_PLAYER);
      IERC20(MORPHO).approve(address(swapper), IERC20(MORPHO).balanceOf(BIGHAND_PLAYER));
      swapper.poolSwap(
        pool,
        init_2nd_token_balance_for_bighand_player - IERC20(MORPHO).balanceOf(BIGHAND_PLAYER),
        WETH > MORPHO, // true if WETH is token0
        0, // amountOutMin - 0 for testing
        "" // empty data
      );
      console.log(
        ">>> lost of bighand player (in wETH):                ",
        IERC20(WETH).balanceOf(BIGHAND_PLAYER) - weth_balance_before
      );
    } else {
      console.log(
        "gain of the bighand player (in MORPHO)",
        IERC20(MORPHO).balanceOf(BIGHAND_PLAYER) - init_2nd_token_balance_for_bighand_player
      );
      console.log("==== (3) bighand converts the gain to wETH to compare ====");
      uint256 weth_balance_before = IERC20(WETH).balanceOf(BIGHAND_PLAYER);
      vm.startPrank(BIGHAND_PLAYER);
      IERC20(MORPHO).approve(address(swapper), IERC20(MORPHO).balanceOf(BIGHAND_PLAYER));
      swapper.poolSwap(
        pool,
        IERC20(MORPHO).balanceOf(BIGHAND_PLAYER) - init_2nd_token_balance_for_bighand_player,
        WETH > MORPHO, // true if WETH is token0
        0, // amountOutMin - 0 for testing
        "" // empty data
      );
      console.log(
        ">>> gain of bighand player (in wETH):                ",
        IERC20(WETH).balanceOf(BIGHAND_PLAYER) - weth_balance_before
      );
    }

    uint256 lost_weth_balance = 998_252_990_397_992_028 - IERC20(WETH).balanceOf(PLAYER_1); // 998252990397992028 is the
    // WETH balance of player 1 if no bighand's swap happens
    console.log(">>> lost weth balance of player 1 after withdrawing: ", lost_weth_balance);

    vm.startPrank(USER);
    console.log("==== user is withdrawing all the shares ====");
    uint256 vaultInstanceBalanceUser = vaultInstance.balanceOf(USER);
    vaultInstance.withdraw(vaultInstanceBalanceUser, false, 0);

    console.log(
      ">>> Summary of case: swapping %d e3 MORPHO -> wETH <<<", init_2nd_token_balance_for_bighand_player / (10 ** 15)
    );
    console.log(">>> WETH balance of user:      ", IERC20(WETH).balanceOf(USER));
    console.log(">>> WETH balance of player 1:  ", IERC20(WETH).balanceOf(PLAYER_1));
    console.log(">>> the share of owner in the vault: ", IERC20(address(vaultInstance)).balanceOf(USER));
    console.log(">>> the share of player 1 in the vault: ", IERC20(address(vaultInstance)).balanceOf(PLAYER_1));
  }
}
