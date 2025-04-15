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
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
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
  ConfigManager public configManager;

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
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);
    LpValidator validator = new LpValidator(address(configManager));
    lpStrategy = new LpStrategy(address(swapper), address(validator));
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

    vm.deal(USER, 100 ether);
    vault.deposit{ value: 0.5 ether }(0.5 ether, 0);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());
    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

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

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

    IERC20(WETH).approve(address(vault), 100 ether);
    vault.deposit(1 ether, 0);
    assertEq(IERC20(vault).balanceOf(USER), 20_003_833_790_858_835_842_737);

    // uint256 wethBalanceBefore = IERC20(WETH).balanceOf(USER);
    console.log("the shares of user before withdraw: %d /1e18", IERC20(vault).balanceOf(USER) / 10 ** 18);
    vault.withdraw(10_000 ether, false, 0);
    console.log("the shares of user after withdraw: %d", IERC20(vault).balanceOf(USER));
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());

    console.log("withdrawing 5000 ether more");
    vault.withdraw(5000 ether, false, 0);
    console.log("the shares of user after withdraw (2): %d", IERC20(vault).balanceOf(USER));
    console.log("the weth balance of user after withdraw (2): %d", IERC20(WETH).balanceOf(USER));
    console.log("the eth balance of user after withdraw (2): %d", address(USER).balance);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());
    console.log("the shares of user after withdraw (2): %d", IERC20(vault).balanceOf(USER));

    console.log("withdrawing everything left");
    vault.withdraw(IERC20(vault).balanceOf(USER), true, 0);
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

  function test_manipulateVaultPosition() public {
    vm.deal(USER, 100 ether);

    assertEq(IERC20(vault).balanceOf(USER), 0.5 ether * vault.SHARES_PRECISION());
    vault.withdraw(0.4 ether * vault.SHARES_PRECISION(), false, 0);
    assertEq(IERC20(vault).balanceOf(USER), 0.1 ether * vault.SHARES_PRECISION());
    console.log("vault.getTotalValue() before: %d", vault.getTotalValue());

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
    // allocate to a low liquidity pool
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
      tickLower: -887_000,
      tickUpper: 887_000,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    console.log("vault.getTotalValue() after: %d", vault.getTotalValue());
    setErc20Balance(WETH, USER, 0);

    for (uint256 i = 0; i < 1; i++) {
      console.log("vault.getTotalValue() before: %d", vault.getTotalValue());
      uint256 newShares = vault.deposit{ value: 1 ether }(1 ether, 0);
      console.log("vault.getTotalValue() middle: %d", vault.getTotalValue());
      console.log("newUser shares: %d", newShares);
      vault.withdraw(newShares, false, 0);
      console.log("newUser WETH withdrawn: %d", IERC20(WETH).balanceOf(USER));
      console.log("vault.getTotalValue() after: %d", vault.getTotalValue());
    }
    console.log("newUser WETH withdrawn: %d", IERC20(WETH).balanceOf(USER));
    console.log("=== withdraw the rest");
    setErc20Balance(WETH, USER, 0);
    vault.withdraw(IERC20(vault).balanceOf(USER), false, 0);
    console.log("newUser WETH withdrawn rest: %d", IERC20(WETH).balanceOf(USER));
  }

  function test_vaultUsdc() public {
    setErc20Balance(USDC, USER, 10_000 * 1e6);

    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(strategies, true);
    vaultConfig = ICommon.VaultConfig({
      principalToken: USDC,
      allowDeposit: false,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      supportedAddresses: new address[](0)
    });

    vault = new Vault();
    IERC20(USDC).transfer(address(vault), 1000 * 1e6);
    ICommon.VaultCreateParams memory createVaultParams = ICommon.VaultCreateParams({
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1000 * 1e6,
      config: vaultConfig
    });
    vault.initialize(createVaultParams, USER, address(configManager), WETH);

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), USDC, 0, 500 * 1e6);
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

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
  }

  function test_vaultWithEmptyPosition() public {
    vm.deal(USER, 100 ether);
    uint256 currentBlock = block.number;

    vault.deposit{ value: 0.5 ether }(0.5 ether, 0);
    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

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

    vm.roll(++currentBlock);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    AssetLib.Asset[] memory inventoryAssets = vault.getInventory();
    AssetLib.Asset memory position;

    for (uint256 i = 0; i < inventoryAssets.length; i++) {
      if (inventoryAssets[i].token == NFPM) {
        position = inventoryAssets[i];
        break;
      }
    }
    uint128 liquidity;
    (,,,,,,, liquidity,,,,) = INFPM(position.token).positions(position.tokenId);
    ILpStrategy.DecreaseLiquidityAndSwapParams memory decreaseParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
      liquidity: liquidity,
      amount0Min: 0,
      amount1Min: 0,
      principalAmountOutMin: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      params: abi.encode(decreaseParams)
    });

    assets[0] = position;
    vm.roll(++currentBlock);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));

    inventoryAssets = vault.getInventory();
    for (uint256 i = 0; i < inventoryAssets.length; i++) {
      if (inventoryAssets[i].token == NFPM) {
        position = inventoryAssets[i];
        break;
      }
    }

    (,,,,,,, liquidity,,,,) = INFPM(position.token).positions(position.tokenId);
    assertEq(liquidity, 0);

    vault.withdraw(IERC20(vault).balanceOf(USER) / 2, false, 0);
    // allocate into the closed position
    {
      assets = new AssetLib.Asset[](2);
      assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.3 ether);
      assets[1] = position;

      ILpStrategy.SwapAndIncreaseLiquidityParams memory increaseParams =
        ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
      instruction = ICommon.Instruction({
        instructionType: uint8(ILpStrategy.InstructionType.SwapAndIncreaseLiquidity),
        params: abi.encode(increaseParams)
      });

      vm.roll(++currentBlock);
      vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    }
  }
}
