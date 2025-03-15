// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { TestCommon, IV3SwapRouter, WETH, DAI, USER, USDC, NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lp/LpStrategy.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";

contract LpStrategyTest is TestCommon {
  LpStrategy public lpStrategy;
  IV3SwapRouter public v3SwapRouter;
  ICommon.VaultConfig public vaultConfig;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
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
    vaultConfig = ICommon.VaultConfig({
      principalToken: WETH,
      allowDeposit: false,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      supportedAddresses: new address[](0)
    });
  }

  function test_LpStrategy() public {
    console.log("==== test_LpStrategy ====");

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });

    console.log("==== mintPosition ====");
    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0 ether);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 77_577_661_546_568_449_798);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== increasePosition ====");
    ILpStrategy.IncreaseLiquidityParams memory increaseParams =
      ILpStrategy.IncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0 });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.IncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    assets = new AssetLib.Asset[](3);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });
    assets[2] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0 ether);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 77_577_661_546_568_449_798);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== rebalancePosition ====");
    ILpStrategy.RebalancePositionParams memory rebalanceParams = ILpStrategy.RebalancePositionParams({
      tickLower: -443_580,
      tickUpper: 443_580,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.RebalancePosition),
      params: abi.encode(rebalanceParams)
    });
    assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 20_464_102_080);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 33);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    (,,,,, int24 tickLower, int24 tickUpper,,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    assertEq(tickLower, -443_580);
    assertEq(tickUpper, 443_580);
    console.log("==== decreasePosition ====");
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityAndSwapParams memory decreaseParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
      liquidity: liquidity / 2,
      amount0Min: 0,
      amount1Min: 0,
      principalAmountOutMin: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      params: abi.encode(decreaseParams)
    });
    assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1_634_761_682_550_505_229);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);

    console.log("==== convertFromPrincipal ====");
    AssetLib.Asset memory existing = returnAssets[2];
    assets = new AssetLib.Asset[](1);
    assets[0] = returnAssets[0];

    transferAssets(assets, address(lpStrategy));
    IERC721(NFPM).transferFrom(USER, address(lpStrategy), existing.tokenId);
    returnAssets = lpStrategy.convertFromPrincipal(existing, assets[0].amount, vaultConfig);
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 3);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 38);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
  }

  function test_LpStrategyMintValidate() public {
    console.log("==== test_LpStrategyMintValidation ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });

    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));

    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));

    assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: USDC,
      tokenId: 0,
      amount: 1_000_000
    });

    mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: DAI,
      token1: USDC,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
  }

  function test_lpStrategyIncreaseValidate() public {
    console.log("==== test_lpStrategyIncreaseValidate ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });

    console.log("==== mintPosition ====");
    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    ILpStrategy.IncreaseLiquidityParams memory increaseParams =
      ILpStrategy.IncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0 });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.IncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
  }

  function test_LpStrategyDecreaseValidate() public {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });

    console.log("==== mintPosition ====");
    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityParams memory decreaseParams =
      ILpStrategy.DecreaseLiquidityParams({ liquidity: liquidity + 1, amount0Min: 0, amount1Min: 0 });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidity),
      params: abi.encode(decreaseParams)
    });
    assets = new AssetLib.Asset[](1);
    assets[0] = returnAssets[2];
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
  }

  function test_LpStrategyRebalanceValidate() public {
    console.log("==== test_LpStrategyRebalanceValidate ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });

    console.log("==== mintPosition ====");
    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));

    ILpStrategy.RebalancePositionParams memory rebalanceParams = ILpStrategy.RebalancePositionParams({
      tickLower: -887_220,
      tickUpper: 887_220,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.RebalancePosition),
      params: abi.encode(rebalanceParams)
    });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
  }

  function test_LpStrategyCompoundValidate() public {
    console.log("==== test_LpStrategyCompoundValidate ====");
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });

    console.log("==== mintPosition ====");
    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887_220,
      tickUpper: 887_220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    ILpStrategy.CompoundParams memory compoundParams = ILpStrategy.CompoundParams({ amount0Min: 0, amount1Min: 0 });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.Compound),
      params: abi.encode(compoundParams)
    });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
  }

  function test_LpStrategyOptimalSwap() public {
    console.log("==== test_LpStrategyOptimalSwap ====");

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 2 ether
    });

    console.log("==== swapAndMintPosition ====");
    ILpStrategy.SwapAndMintPositionParams memory mintParams = ILpStrategy.SwapAndMintPositionParams({
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
      params: abi.encode(mintParams)
    });
    transferAssets(assets, address(lpStrategy));
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 9694);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== swapAndIncreasePosition ====");
    ILpStrategy.SwapAndIncreaseLiquidityParams memory increaseParams =
      ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndIncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 340_659_039);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== swapAndRebalancePosition ====");
    ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
      tickLower: -443_580,
      tickUpper: 443_580,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndRebalancePosition),
      params: abi.encode(rebalanceParams)
    });
    assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 691_759_402);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== swapAndCompound ====");
    ILpStrategy.SwapAndCompoundParams memory compoundParams =
      ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndCompound),
      params: abi.encode(compoundParams)
    });
    assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 373_621_692);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== decreasePositionAndSwap ====");
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityAndSwapParams memory decreaseParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
      liquidity: liquidity / 2,
      amount0Min: 0,
      amount1Min: 0,
      principalAmountOutMin: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      params: abi.encode(decreaseParams)
    });
    assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 374_638_097_833_681_952);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
  }
}
