// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, IV3SwapRouter } from "../TestCommon.t.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { AssetLib } from "../../contracts/libraries/AssetLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { console } from "forge-std/console.sol";

contract VaultTest is TestCommon {
  address public constant WETH = 0x4200000000000000000000000000000000000006;
  address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
  address public constant USER = 0x1234567890123456789012345678901234567890;
  address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address public constant NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
  LpStrategy public lpStrategy;
  IV3SwapRouter public v3SwapRouter;
  ICommon.VaultConfig public vaultConfig;
  Vault public vault;
  address public constant USER_2 = 0x0000000000000000000000000000000000000001;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);
    vm.startBroadcast(USER);
    setErc20Balance(WETH, USER, 100 ether);
    setErc20Balance(DAI, USER, 100_000 ether);
    setErc20Balance(USDC, USER, 1_000_000_000); // 6 decimals ~ 1000$

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();

    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(ILpStrategy.TokenType.Stable);
    typedTokenTypes[1] = uint256(ILpStrategy.TokenType.Stable);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    ConfigManager configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);

    lpStrategy = new LpStrategy(address(swapper), address(configManager));
    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(strategies, true);
    vaultConfig = ICommon.VaultConfig({
      principalToken: WETH,
      allowDeposit: false,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      supportedAddresses: new address[](0)
    });

    vault = new Vault();
    IERC20(WETH).transfer(address(vault), 0.5 ether);
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0.5 ether,
      config: vaultConfig
    });
    vault.initialize(params, USER, address(configManager), WETH);
  }

  function test_Vault() public {
    assertEq(IERC20(vault).balanceOf(USER), 0.5 ether * vault.SHARES_PRECISION());

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.8 ether);
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
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());

    vm.deal(USER, 100 ether);
    vault.deposit{ value: 0.5 ether }(0.5 ether, 0);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());

    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

    IERC20(WETH).approve(address(vault), 100 ether);
    vault.deposit(1 ether, 0);
    assertEq(IERC20(vault).balanceOf(USER), 20_001_958_738_672_832_443_901);

    // uint256 wethBalanceBefore = IERC20(WETH).balanceOf(USER);
    console.log("the shares of user before withdraw: %d /1e18", IERC20(vault).balanceOf(USER) / 10 ** 18);
    vault.withdraw(10_000 ether, false);
    console.log("the shares of user after withdraw: %d", IERC20(vault).balanceOf(USER));
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());

    console.log("withdrawing 5000 ether more");
    vault.withdraw(5000 ether, false);
    console.log("the shares of user after withdraw (2): %d", IERC20(vault).balanceOf(USER));
    console.log("the weth balance of user after withdraw (2): %d", IERC20(WETH).balanceOf(USER));
    console.log("the eth balance of user after withdraw (2): %d", address(USER).balance);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());
    console.log("the shares of user after withdraw (2): %d", IERC20(vault).balanceOf(USER));

    console.log("withdrawing everything left");
    vault.withdraw(IERC20(vault).balanceOf(USER), true);
    console.log("the shares of user after withdraw (3): %d", IERC20(vault).balanceOf(USER));
    console.log("the weth balance of user after withdraw (3): %d", IERC20(WETH).balanceOf(USER));
    console.log("the eth balance of user after withdraw (3): %d", address(USER).balance);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());
    console.log("the shares of user after withdraw (3): %d", IERC20(vault).balanceOf(USER));
    assertEq(IERC20(vault).balanceOf(USER), 0);
  }

  function test_allow_deposit() public {
    console.log("==== User can turn ON allow_deposit for his private vault ====");
    vaultConfig.allowDeposit = true;
    vaultConfig.supportedAddresses = new address[](1);
    console.log("vaultConfig.allowDeposit: %s", vaultConfig.allowDeposit);
    console.log("vaultConfig.supportedAddresses: %s", vaultConfig.supportedAddresses.length);
    console.log("vaultConfig.principalToken: %s", vaultConfig.principalToken);
    vault.allowDeposit(vaultConfig);
    (bool allowDeposit,,,,) = vault.getVaultConfig();
    assertEq(allowDeposit, true);
    console.log("The vault is public now");

    console.log("==== User can't turn OFF allow_deposit for his public vault ====");
    vaultConfig.allowDeposit = false;
    vaultConfig.supportedAddresses = new address[](0);
    console.log("vaultConfig.allowDeposit: %s", vaultConfig.allowDeposit);
    console.log("vaultConfig.supportedAddresses: %s", vaultConfig.supportedAddresses.length);
    vm.expectRevert(ICommon.InvalidVaultConfig.selector);
    vault.allowDeposit(vaultConfig);
  }
}
