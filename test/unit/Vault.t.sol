// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, IV3SwapRouter } from "../TestCommon.t.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { AssetLib } from "../../contracts/libraries/AssetLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { console } from "forge-std/console.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

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
  PoolOptimalSwapper public swapper;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);
    vm.startBroadcast(USER);
    setErc20Balance(WETH, USER, 100 ether);
    setErc20Balance(DAI, USER, 100_000 ether);
    setErc20Balance(USDC, USER, 1_000_000_000); // 6 decimals ~ 1000$

    swapper = new PoolOptimalSwapper();

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
    whitelistNfpms[0] = address(NFPM);
    LpValidator validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));
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
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0.5 ether,
      config: vaultConfig
    });
    vault.initialize(params, USER, USER, address(configManager), WETH);
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

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    console.log("vault.getTotalValue() 2: %d", vault.getTotalValue());
    assertEq(IERC20(vault).balanceOf(USER), 1 ether * vault.SHARES_PRECISION());

    IERC20(WETH).approve(address(vault), 100 ether);
    vault.deposit(1 ether, 0);
    assertApproxEqRel(IERC20(vault).balanceOf(USER), 20_000 ether, TOLERANCE);

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
    vault.allowDeposit(vaultConfig, 0);
    (bool allowDeposit,,,,,) = vault.getVaultConfig();
    assertEq(allowDeposit, true);
    console.log("The vault is public now");

    console.log("==== User can't turn OFF allow_deposit for his public vault ====");
    vaultConfig.allowDeposit = false;
    vaultConfig.supportedAddresses = new address[](0);
    console.log("vaultConfig.allowDeposit: %s", vaultConfig.allowDeposit);
    console.log("vaultConfig.supportedAddresses: %s", vaultConfig.supportedAddresses.length);
    vm.expectRevert(ICommon.InvalidVaultConfig.selector);
    vault.allowDeposit(vaultConfig, 0);
  }

  function test_manipulateVaultPosition_lowLiquidity() public {
    vm.deal(USER, 10_000 ether);

    // assertEq(IERC20(vault).balanceOf(USER), 0.5 ether * vault.SHARES_PRECISION());
    // vault.withdraw(0.4 ether * vault.SHARES_PRECISION(), false, 0);
    // assertEq(IERC20(vault).balanceOf(USER), 0.1 ether * vault.SHARES_PRECISION());
    uint256 ownerValueBefore = vault.getTotalValue();

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
    // allocate to a low liquidity pool
    console.log("allocate to a low liquidity pool");
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
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

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    setErc20Balance(WETH, USER, 0);
    uint256 depositValue = 1 ether;

    for (uint256 i = 0; i < 10; i++) {
      console.log("vault.getTotalValue() before: %d", vault.getTotalValue());
      uint256 newShares = vault.deposit{ value: depositValue }(depositValue, 0);
      console.log("newUser shares: %d", newShares);
      setErc20Balance(WETH, USER, 0);
      vault.withdraw(newShares, false, 0);
      console.log("depositValue: %d", depositValue);
      console.log("newUser WETH withdrawn: %d", IERC20(WETH).balanceOf(USER));
      console.log(
        "newUser WETH withdrawn must be < depositValue: ", int256(depositValue) - int256(IERC20(WETH).balanceOf(USER))
      );
      console.log("vault.getTotalValue() after: %d", vault.getTotalValue());
    }
    console.log("newUser WETH withdrawn: %d", IERC20(WETH).balanceOf(USER));
    console.log("=== withdraw the rest");
    setErc20Balance(WETH, USER, 0);
    vault.withdraw(IERC20(vault).balanceOf(USER), false, 0);
    uint256 ownerValueAfter = IERC20(WETH).balanceOf(USER);
    console.log("newUser WETH withdrawn rest: %d", IERC20(WETH).balanceOf(USER));
    console.log("expecting ownerValueAfter must be greater than ownerValueBefore");
    console.log("delta", int256(ownerValueAfter) - int256(ownerValueBefore));
  }

  function test_manipulateVaultPosition_highLiquidity() public {
    vm.deal(USER, 10_000 ether);

    // assertEq(IERC20(vault).balanceOf(USER), 0.5 ether * vault.SHARES_PRECISION());
    // vault.withdraw(0.4 ether * vault.SHARES_PRECISION(), false, 0);
    // assertEq(IERC20(vault).balanceOf(USER), 0.1 ether * vault.SHARES_PRECISION());

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.1 ether);
    // allocate to a low liquidity pool
    console.log("allocate to a high liquidity pool");
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
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
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    setErc20Balance(WETH, USER, 0);
    uint256 ownerValueBefore = vault.getTotalValue();
    uint256 depositValue = 1 ether;
    for (uint256 i = 0; i < 10; i++) {
      console.log("vault.getTotalValue() before: %d", vault.getTotalValue());
      uint256 newShares = vault.deposit{ value: depositValue }(depositValue, 0);
      console.log("newUser shares: %d", newShares);
      setErc20Balance(WETH, USER, 0);
      vault.withdraw(newShares, false, 0);
      console.log("depositValue: %d", depositValue);
      console.log("newUser WETH withdrawn: %d", IERC20(WETH).balanceOf(USER));
      console.log(
        "newUser WETH withdrawn must be < depositValue: ", int256(depositValue) - int256(IERC20(WETH).balanceOf(USER))
      );
      console.log("vault.getTotalValue() after: %d", vault.getTotalValue());
    }
    console.log("newUser WETH withdrawn: %d", IERC20(WETH).balanceOf(USER));
    console.log("=== withdraw the rest");
    setErc20Balance(WETH, USER, 0);
    uint256 ownerValueAfter = vault.getTotalValue();
    vault.withdraw(IERC20(vault).balanceOf(USER), false, 0);
    console.log("newUser WETH withdrawn rest: %d", IERC20(WETH).balanceOf(USER));
    console.log("expecting ownerValueAfter must be greater than ownerValueBefore");
    console.log("delta", int256(ownerValueAfter) - int256(ownerValueBefore));
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
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1000 * 1e6,
      config: vaultConfig
    });
    vault.initialize(createVaultParams, USER, USER, address(configManager), WETH);

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

    vm.expectRevert(IVault.ExceedMaxAllocatePerBlock.selector);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));

    configManager.setVaultPaused(true);
    vm.expectRevert(IVault.VaultPaused.selector);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    configManager.setVaultPaused(false);

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
    // cannot allocate into the closed position
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

      vm.expectRevert();
      vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    }
  }

  function test_vaultMigrateLp() public {
    console.log("===== test_vaultMigrateLp =====");
    assertEq(IERC20(vault).balanceOf(USER), 0.5 ether * vault.SHARES_PRECISION());
    uint256 blockNumber = block.number;

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

    vm.roll(blockNumber++);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));

    vm.roll(blockNumber++);
    console.log("===== deploy new lpStrategy =====");

    address[] memory whitelistNfpms = new address[](1);
    whitelistNfpms[0] = address(NFPM);

    LpValidator validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    LpStrategy newLpStrategy =
      new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));

    console.log("===== remove lpStrategy from whitelist =====");
    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(strategies, false);

    console.log("===== add newLpStrategy to whitelist =====");
    strategies[0] = address(newLpStrategy);
    configManager.whitelistStrategy(strategies, true);

    console.log("===== position cannot be decrease =====");
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

    vm.roll(blockNumber++);
    vm.expectRevert(ICommon.InvalidStrategy.selector);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));

    vm.roll(blockNumber++);
    console.log("===== position can be decrease using new lpStrategy =====");
    console.log("===== lpStrategy address: %s", address(lpStrategy));
    vault.allocate(assets, newLpStrategy, 0, abi.encode(instruction));
  }

  function test_VaultAllocateAllPrincipal() public {
    assertEq(IERC20(vault).balanceOf(USER), 0.5 ether * vault.SHARES_PRECISION());
    vault.withdraw(0.5 ether * vault.SHARES_PRECISION(), false, 0);

    vault.deposit{ value: 0.001 ether }(0.001 ether, 0);
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    AssetLib.Asset[] memory inventoryAssets = vault.getInventory();
    assets[0] = inventoryAssets[0];
    {
      for (uint256 i = 0; i < inventoryAssets.length; i++) {
        console.log("inventoryAssets[%d].token: %s", i, inventoryAssets[i].token);
        console.log("amount: %d", inventoryAssets[i].amount);
      }
    }

    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(WETH, USDC, 500);
    (, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();
    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
      tickLower: ((tick - 20) / 10) * 10,
      tickUpper: ((tick - 10) / 10) * 10,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });

    vm.roll(block.number + 1);
    vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
    {
      console.log("after");
      inventoryAssets = vault.getInventory();
      for (uint256 i = 0; i < inventoryAssets.length; i++) {
        console.log("inventoryAssets[%d].token: %s", i, inventoryAssets[i].token);
        console.log("amount: %d", inventoryAssets[i].amount);
      }
    }

    // swap to generate fee
    IERC20(USDC).approve(address(swapper), 100 ether);
    setErc20Balance(USDC, USER, 100 ether);
    swapper.poolSwap(pool, 100_000 * 10 ** 6, false, 0, "");
    IERC20(WETH).approve(address(swapper), 100 ether);
    swapper.poolSwap(pool, 100 ether, true, 0, "");

    console.log("withdrawing everything left");
    vault.withdraw(IERC20(vault).balanceOf(USER), true, 0);
    console.log("the shares of user after withdraw (3): %d", IERC20(vault).balanceOf(USER));
    console.log("the weth balance of user after withdraw (3): %d", IERC20(WETH).balanceOf(USER));
    console.log("the eth balance of user after withdraw (3): %d", address(USER).balance);
    console.log("vault.getTotalValue(): %d", vault.getTotalValue());
    console.log("the shares of user after withdraw (3): %d", IERC20(vault).balanceOf(USER));
    assertEq(IERC20(vault).balanceOf(USER), 0);
  }

  // =====================
  // depositPrincipal tests
  // =====================
  function test_depositPrincipal_happy_ERC20() public {
    // Only admin/automator, private vault, amount > 0
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    deal(WETH, USER, 1 ether);
    IERC20(WETH).approve(address(v), 1 ether);
    uint256 shares = v.depositPrincipal(1 ether);
    assertEq(IERC20(WETH).balanceOf(address(v)), 1 ether);
    assertEq(shares, 1 ether * v.SHARES_PRECISION());
    assertEq(IERC20(v).balanceOf(USER), shares);
  }

  function test_depositPrincipal_happy_ETH() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.deal(USER, 1 ether);
    uint256 startBal = USER.balance;
    uint256 shares = v.depositPrincipal{ value: 1 ether }(1 ether);
    assertEq(IERC20(WETH).balanceOf(address(v)), 1 ether);
    assertEq(shares, 1 ether * v.SHARES_PRECISION());
    assertEq(IERC20(v).balanceOf(USER), shares);
    assertEq(USER.balance, startBal - 1 ether);
  }

  function test_depositPrincipal_happy_ERC201() public {
    // Only admin/automator, private vault, amount > 0
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    IERC20(WETH).transfer(address(v), 1 ether);
    v.initialize(params, USER, USER, address(configManager), WETH);
    deal(WETH, USER, 1 ether);
    IERC20(WETH).approve(address(v), 1 ether);
    uint256 shares = v.depositPrincipal(1 ether);
    assertEq(IERC20(WETH).balanceOf(address(v)), 2 ether);
    assertEq(shares, 1 ether * v.SHARES_PRECISION());
    assertEq(IERC20(v).balanceOf(USER), 2 ether * v.SHARES_PRECISION());
    // withdrawPrincipal 2 ether
    uint256 balBefore = IERC20(WETH).balanceOf(USER);
    v.withdrawPrincipal(2 ether, false);
    assertEq(IERC20(WETH).balanceOf(address(v)), 0);
    assertEq(IERC20(v).balanceOf(USER), 0);
    assertEq(IERC20(WETH).balanceOf(USER), balBefore + 2 ether);
    // redeposit principal 1 ether
    IERC20(WETH).approve(address(v), 1 ether);
    shares = v.depositPrincipal(1 ether);
    assertEq(IERC20(WETH).balanceOf(address(v)), 1 ether);
    assertEq(shares, 1 ether * v.SHARES_PRECISION());
    assertEq(IERC20(v).balanceOf(USER), shares);
  }

  function test_depositPrincipal_happy_ETH1() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    IERC20(WETH).transfer(address(v), 1 ether);
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.deal(USER, 1 ether);
    uint256 startBal = USER.balance;
    uint256 shares = v.depositPrincipal{ value: 1 ether }(1 ether);
    assertEq(IERC20(WETH).balanceOf(address(v)), 2 ether);
    assertEq(shares, 1 ether * v.SHARES_PRECISION());
    assertEq(IERC20(v).balanceOf(USER), 2 ether * v.SHARES_PRECISION());
    assertEq(USER.balance, startBal - 1 ether);
  }

  function test_depositPrincipal_fail_notAdmin() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.stopBroadcast();
    vm.startBroadcast(address(this));
    vm.expectRevert(IVault.Unauthorized.selector);
    v.depositPrincipal(1 ether);
    vm.stopBroadcast();
    vm.startBroadcast(USER);
  }

  function test_depositPrincipal_fail_notPrivateVault() public {
    vaultConfig.allowDeposit = true;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.expectRevert(IVault.DepositAllowed.selector);
    v.depositPrincipal(1 ether);
  }

  // function test_depositPrincipal_fail_zeroAmount() public {
  //   vaultConfig.allowDeposit = false;
  //   ICommon.VaultCreateParams memory params =
  //     ICommon.VaultCreateParams({
  // vaultOwnerFeeBasisPoint: 0, name: "TestVault", symbol: "TV", principalTokenAmount: 0, config: vaultConfig });
  //   Vault v = new Vault();
  //   v.initialize(params, USER, USER, address(configManager), WETH);
  //   vm.expectRevert(IVault.InvalidAssetAmount.selector);
  //   v.depositPrincipal(0);
  // }

  function test_depositPrincipal_fail_wrongETHtoken() public {
    // principalToken != WETH, but ETH sent
    vaultConfig.allowDeposit = false;
    vaultConfig.principalToken = USDC;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.deal(USER, 2 ether);
    vm.expectRevert(IVault.InvalidAssetToken.selector);
    v.depositPrincipal{ value: 1 ether }(1 ether);
  }

  function test_depositPrincipal_fail_wrongETHamount() public {
    // ETH sent != principalAmount
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.deal(USER, 2 ether);
    vm.expectRevert(IVault.InvalidAssetAmount.selector);
    v.depositPrincipal{ value: 2 ether }(1 ether);
  }

  // =====================
  // withdrawPrincipal tests
  // =====================
  function test_withdrawPrincipal_happy_ERC20() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    IERC20(WETH).transfer(address(v), 1 ether);
    v.initialize(params, USER, USER, address(configManager), WETH);
    v.getInventory(); // Initialize inventory
    uint256 balBefore = IERC20(WETH).balanceOf(USER);
    v.withdrawPrincipal(1 ether, false);
    assertEq(IERC20(WETH).balanceOf(address(v)), 0);
    assertEq(IERC20(v).balanceOf(USER), 0);
    assertEq(IERC20(WETH).balanceOf(USER), balBefore + 1 ether);
  }

  function test_withdrawPrincipal_happy_unwrapWETH() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    IERC20(WETH).transfer(address(v), 1 ether);
    v.initialize(params, USER, USER, address(configManager), WETH);
    v.getInventory(); // Initialize inventory
    uint256 balBefore = USER.balance;
    v.withdrawPrincipal(1 ether, true);
    assertEq(address(v).balance, 0);
    assertEq(IERC20(WETH).balanceOf(address(v)), 0);
    assertEq(IERC20(v).balanceOf(USER), 0);
    assertEq(USER.balance, balBefore + 1 ether);
  }

  function test_withdrawPrincipal_happy_ERC202() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 2 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    IERC20(WETH).transfer(address(v), 2 ether);
    v.initialize(params, USER, USER, address(configManager), WETH);
    v.getInventory(); // Initialize inventory
    uint256 balBefore = IERC20(WETH).balanceOf(USER);
    v.withdrawPrincipal(1 ether, false);
    assertEq(IERC20(WETH).balanceOf(address(v)), 1 ether);
    assertEq(IERC20(v).balanceOf(USER), 1 ether * v.SHARES_PRECISION());
    assertEq(IERC20(WETH).balanceOf(USER), balBefore + 1 ether);
  }

  function test_withdrawPrincipal_happy_unwrapWETH2() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 2 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    IERC20(WETH).transfer(address(v), 2 ether);
    v.initialize(params, USER, USER, address(configManager), WETH);
    v.getInventory(); // Initialize inventory
    uint256 balBefore = USER.balance;
    v.withdrawPrincipal(1 ether, true);
    assertEq(IERC20(WETH).balanceOf(address(v)), 1 ether);
    assertEq(IERC20(v).balanceOf(USER), 1 ether * v.SHARES_PRECISION());
    assertEq(address(v).balance, 0);
    assertEq(USER.balance, balBefore + 1 ether);
  }

  function test_withdrawPrincipal_fail_notAdmin() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.stopBroadcast();
    vm.startBroadcast(address(this));
    vm.expectRevert(IVault.Unauthorized.selector);
    v.withdrawPrincipal(1 ether, false);
    vm.stopBroadcast();
    vm.startBroadcast(USER);
  }

  function test_withdrawPrincipal_fail_notPrivateVault() public {
    vaultConfig.allowDeposit = true;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.expectRevert(IVault.DepositAllowed.selector);
    v.withdrawPrincipal(1 ether, false);
  }

  // function test_withdrawPrincipal_fail_zeroAmount() public {
  //   vaultConfig.allowDeposit = false;
  //   ICommon.VaultCreateParams memory params =
  //     ICommon.VaultCreateParams({
  // vaultOwnerFeeBasisPoint: 0, name: "TestVault", symbol: "TV", principalTokenAmount: 1 ether, config: vaultConfig
  // });
  //   Vault v = new Vault();
  //   v.initialize(params, USER, USER, address(configManager), WETH);
  //   vm.expectRevert(IVault.InvalidAssetAmount.selector);
  //   v.withdrawPrincipal(0, false);
  // }

  function test_withdrawPrincipal_fail_insufficientBalance() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 0.5 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    vm.expectRevert(); // Should revert due to insufficient asset
    v.withdrawPrincipal(1 ether, false);
  }

  // =====================
  // harvestPrivate tests
  // =====================
  function test_harvestPrivate_fail_notAdmin() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    // Allocate to strategy
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    vm.stopBroadcast();
    vm.startBroadcast(address(this));
    vm.expectRevert(IVault.Unauthorized.selector);
    v.harvestPrivate(assets, false, 0, 0);
    vm.stopBroadcast();
    vm.startBroadcast(USER);
  }

  function test_harvestPrivate_fail_notPrivateVault() public {
    vaultConfig.allowDeposit = true;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    vm.expectRevert(IVault.DepositAllowed.selector);
    v.harvestPrivate(assets, false, 0, 0);
  }

  function test_harvestPrivate_fail_noStrategy() public {
    vaultConfig.allowDeposit = false;
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "TestVault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: vaultConfig
    });
    Vault v = new Vault();
    v.initialize(params, USER, USER, address(configManager), WETH);
    // Asset with no strategy
    AssetLib.Asset[] memory toHarvest = new AssetLib.Asset[](1);
    toHarvest[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    vm.expectRevert(IVault.InvalidAssetStrategy.selector);
    v.harvestPrivate(toHarvest, false, 0, 0);
  }
}
