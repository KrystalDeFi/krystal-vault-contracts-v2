// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { TestCommon, IV3SwapRouter, WETH, DAI, USER, USDC, NFPM, PLATFORM_WALLET } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LpStrategyTest is TestCommon {
  LpStrategy public lpStrategy;
  IV3SwapRouter public v3SwapRouter;
  ICommon.VaultConfig public vaultConfig;
  ICommon.FeeConfig public feeConfig;
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
    typedTokenTypes[0] = uint256(ILpStrategy.TokenType.Stable);
    typedTokenTypes[1] = uint256(ILpStrategy.TokenType.Stable);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    ConfigManager configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);

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
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    // ILpStrategy.RebalancePositionParams memory rebalanceParams = ILpStrategy.RebalancePositionParams({
    //   tickLower: -443_580,
    //   tickUpper: 443_580,
    //   decreasedAmount0Min: 0,
    //   decreasedAmount1Min: 0,
    //   amount0Min: 0,
    //   amount1Min: 0
    // });
    // instruction = ICommon.Instruction({
    //   instructionType: uint8(ILpStrategy.InstructionType.RebalancePosition),
    //   params: abi.encode(rebalanceParams)
    // });
    // assets = new AssetLib.Asset[](1);
    // assets[0] = AssetLib.Asset({
    //   assetType: AssetLib.AssetType.ERC721,
    //   strategy: address(lpStrategy),
    //   token: NFPM,
    //   tokenId: returnAssets[2].tokenId,
    //   amount: 1
    // });
    // transferAssets(assets, address(lpStrategy));
    // returnAssets = lpStrategy.convert(assets, vaultConfig, abi.encode(instruction));
    // assertEq(returnAssets.length, 3);
    // assertEq(returnAssets[0].token, WETH);
    // assertEq(returnAssets[0].amount, 20_464_102_080);
    // assertEq(returnAssets[1].token, DAI);
    // assertEq(returnAssets[1].amount, 33);
    // assertEq(returnAssets[2].token, NFPM);
    // assertEq(returnAssets[2].amount, 1);
    // assertNotEq(returnAssets[2].tokenId, 0);
    // assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    // (,,,,, int24 tickLower, int24 tickUpper,,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    // assertEq(tickLower, -443_580);
    // assertEq(tickUpper, 443_580);
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
    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1_634_761_692_781_853_501);
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
    assertEq(returnAssets[0].amount, 0);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 1109);
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
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));

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
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    ILpStrategy.IncreaseLiquidityParams memory increaseParams =
      ILpStrategy.IncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0 });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.IncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityParams memory decreaseParams =
      ILpStrategy.DecreaseLiquidityParams({ liquidity: liquidity + 1, amount0Min: 0, amount1Min: 0 });
    instruction = ICommon.Instruction({ instructionType: type(uint8).max, params: abi.encode(decreaseParams) });
    assets = new AssetLib.Asset[](1);
    assets[0] = returnAssets[2];
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));

    ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
      tickLower: -887_220,
      tickUpper: 887_220,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({ instructionType: type(uint8).max, params: abi.encode(rebalanceParams) });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    ILpStrategy.SwapAndCompoundParams memory compoundParams =
      ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
    instruction = ICommon.Instruction({ instructionType: type(uint8).max, params: abi.encode(compoundParams) });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
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
    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1864);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 1);
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
    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0);
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
    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1_499_264_827_661_936_896);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
  }

  function test_LpStrategyFeeTaker() public {
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
    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(WETH, DAI, 3000);

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
    AssetLib.Asset[] memory returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    IERC20(WETH).approve(address(swapper), 1 ether);
    (uint256 amountOut,) = swapper.poolSwap(pool, 1 ether, true, 0, "");
    IERC20(DAI).approve(address(swapper), amountOut);
    swapper.poolSwap(pool, amountOut, false, 0, "");
    // uint256 fee0 = 2_556_795_487_525_688;
    // uint256 fee1 = 2_651_766_154_928_366_678;

    address mockVaultOwner = address(0x100);
    address mockPlatformWallet = address(0x200);
    address mockGasFeeRecipient = address(0x300);
    ICommon.FeeConfig memory openFeeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 500,
      vaultOwner: mockVaultOwner,
      platformFeeBasisPoint: 1000,
      platformFeeRecipient: mockPlatformWallet,
      gasFeeBasisPoint: 1500,
      gasFeeRecipient: mockGasFeeRecipient
    });
    console.log("==== test take fee when harvest ====");
    transferAsset(returnAssets[2], address(lpStrategy));
    returnAssets = lpStrategy.harvest(returnAssets[2], WETH, openFeeConfig);

    assertEq(returnAssets.length, 3);
    assertEq(IERC20(WETH).balanceOf(mockVaultOwner), 196_680_692_884_358);
    assertEq(IERC20(DAI).balanceOf(mockVaultOwner), 0);
    assertEq(IERC20(WETH).balanceOf(mockPlatformWallet), 393_361_385_768_717);
    assertEq(IERC20(DAI).balanceOf(mockPlatformWallet), 0);
    assertEq(IERC20(WETH).balanceOf(mockGasFeeRecipient), 590_042_078_653_075);
    assertEq(IERC20(DAI).balanceOf(mockGasFeeRecipient), 0);
    assertEq(returnAssets[0].amount, 2_753_529_700_381_020);
    assertEq(returnAssets[1].amount, 0);

    console.log("==== test take fee when swap and compound ====");
    console.log("==== swapAndCompound ====");
    // do another swap to generate fee
    setErc20Balance(WETH, mockVaultOwner, 0);
    setErc20Balance(DAI, mockVaultOwner, 0);
    setErc20Balance(WETH, mockPlatformWallet, 0);
    setErc20Balance(DAI, mockPlatformWallet, 0);
    setErc20Balance(WETH, mockGasFeeRecipient, 0);
    setErc20Balance(DAI, mockGasFeeRecipient, 0);

    IERC20(WETH).approve(address(swapper), 1 ether);
    (amountOut,) = swapper.poolSwap(pool, 1 ether, true, 0, "");
    IERC20(DAI).approve(address(swapper), amountOut);
    swapper.poolSwap(pool, amountOut, false, 0, "");
    lpStrategy.valueOf(returnAssets[2], WETH);
    uint256 fee0 = 2_557_154_124_851_458;
    uint256 fee1 = 2_655_711_330_991_053_790;

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
    returnAssets = lpStrategy.convert(assets, vaultConfig, openFeeConfig, abi.encode(instruction));

    assertEq(IERC20(WETH).balanceOf(mockVaultOwner), fee0 * 500 / 10_000, "vault owner fee 0");
    assertEq(IERC20(DAI).balanceOf(mockVaultOwner), fee1 * 500 / 10_000, "vault owner fee 1");
    assertEq(IERC20(WETH).balanceOf(mockPlatformWallet), fee0 * 1000 / 10_000, "platform fee 0");
    assertEq(IERC20(DAI).balanceOf(mockPlatformWallet), fee1 * 1000 / 10_000, "platform fee 1");
    assertEq(IERC20(WETH).balanceOf(mockGasFeeRecipient), fee0 * 1500 / 10_000, "gas fee 0");
    assertEq(IERC20(DAI).balanceOf(mockGasFeeRecipient), fee1 * 1500 / 10_000, "gas fee 1");

    console.log("==== test take fee when decrease liquidity ====");
    setErc20Balance(WETH, mockVaultOwner, 0);
    setErc20Balance(DAI, mockVaultOwner, 0);
    setErc20Balance(WETH, mockPlatformWallet, 0);
    setErc20Balance(DAI, mockPlatformWallet, 0);
    setErc20Balance(WETH, mockGasFeeRecipient, 0);
    setErc20Balance(DAI, mockGasFeeRecipient, 0);

    // do another swap to generate fee
    IERC20(WETH).approve(address(swapper), 1 ether);
    (amountOut,) = swapper.poolSwap(pool, 1 ether, true, 0, "");
    IERC20(DAI).approve(address(swapper), amountOut);
    swapper.poolSwap(pool, amountOut, false, 0, "");
    lpStrategy.valueOf(returnAssets[2], WETH);
    fee0 = 2_560_426_929_595_547;
    fee1 = 2_649_488_043_479_605_912;

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
    returnAssets = lpStrategy.convert(assets, vaultConfig, openFeeConfig, abi.encode(instruction));

    assertEq(IERC20(WETH).balanceOf(mockVaultOwner), fee0 * 500 / 10_000, "vault owner fee 0");
    assertEq(IERC20(DAI).balanceOf(mockVaultOwner), fee1 * 500 / 10_000, "vault owner fee 1");
    assertEq(IERC20(WETH).balanceOf(mockPlatformWallet), fee0 * 1000 / 10_000, "platform fee 0");
    assertEq(IERC20(DAI).balanceOf(mockPlatformWallet), fee1 * 1000 / 10_000, "platform fee 1");
    assertEq(IERC20(WETH).balanceOf(mockGasFeeRecipient), fee0 * 1500 / 10_000, "gas fee 0");
    assertEq(IERC20(DAI).balanceOf(mockGasFeeRecipient), fee1 * 1500 / 10_000, "gas fee 1");
  }
}
