// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {TestCommon, IV3SwapRouter} from "./TestCommon.t.sol";
import {LpStrategy} from "../contracts/strategies/lp/LpStrategy.sol";
import {ICommon} from "../contracts/interfaces/ICommon.sol";
import {PoolOptimalSwapper} from "../contracts/core/PoolOptimalSwapper.sol";
import {ConfigManager} from "../contracts/core/ConfigManager.sol";
import {Vault} from "../contracts/core/Vault.sol";
import {AssetLib} from "../contracts/libraries/AssetLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILpStrategy} from "../contracts/interfaces/strategies/ILpStrategy.sol";
import {INonfungiblePositionManager as INFPM} from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {console} from "forge-std/console.sol";

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
    uint256 fork = vm.createFork(
      "https://base-mainnet.infura.io/v3/117e1c71984843059b080dc9c9f57c66", 27_448_360
    );
    vm.selectFork(fork);
    vm.startBroadcast(USER);
    setErc20Balance(WETH, USER, 100 ether);
    setErc20Balance(DAI, USER, 100_000 ether);
    setErc20Balance(USDC, USER, 1_000_000_000); // 6 decimals ~ 1000$

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();

    address[] memory stableTokens = new address[](2);
    stableTokens[0] = DAI;
    stableTokens[1] = USDC;
    ConfigManager configManager = new ConfigManager(stableTokens);

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
      ownerFeeBasisPoint: 100,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0.5 ether,
      config: vaultConfig
    });
    vault.initialize(params, USER, address(configManager), address(0));
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

    IERC20(WETH).approve(address(vault), 100 ether);
    vault.deposit(0.5 ether);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());

    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

    vault.allocate(assets, lpStrategy, abi.encode(instruction));
    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

    vault.deposit(1 ether);
    assertEq(IERC20(vault).balanceOf(USER), 20_001_958_738_672_832_443_901);

    uint256 wethBalanceBefore = IERC20(WETH).balanceOf(USER);
    vault.withdraw(10_000 ether);
    assertEq(IERC20(vault).balanceOf(USER), 10_001_958_738_672_832_443_901);
    assertEq(IERC20(WETH).balanceOf(USER), wethBalanceBefore + 1 ether);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());
  }
}
