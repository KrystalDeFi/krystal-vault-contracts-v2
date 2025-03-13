// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, IV3SwapRouter } from "./TestCommon.t.sol";
import { LpStrategy } from "../contracts/strategies/lp/LpStrategy.sol";
import { ICommon } from "../contracts/interfaces/ICommon.sol";
import { ILpStrategy } from "../contracts/interfaces/strategies/ILpStrategy.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { console } from "forge-std/console.sol";
import { PoolOptimalSwapper } from "../contracts/core/PoolOptimalSwapper.sol";

contract LpStrategyTest is TestCommon {
  address public constant WETH = 0x4200000000000000000000000000000000000006;
  address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
  address public constant USER = 0x1234567890123456789012345678901234567890;
  address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address public constant NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
  LpStrategy public lpStrategy;
  IV3SwapRouter public v3SwapRouter;

  function setUp() public {
    uint256 fork = vm.createFork("https://base-mainnet.infura.io/v3/117e1c71984843059b080dc9c9f57c66", 27_448_360);
    vm.selectFork(fork);
    vm.startBroadcast(USER);
    setErc20Balance(WETH, USER, 100 ether);
    setErc20Balance(DAI, USER, 100_000 ether);
    setErc20Balance(USDC, USER, 1_000_000_000); // 6 decimals ~ 1000$

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();

    lpStrategy = new LpStrategy(WETH, address(swapper));
  }

  function test_LpStrategy() public {
    console.log("==== test_LpStrategy ====");

    ICommon.Asset[] memory assets = new ICommon.Asset[](2);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
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
    ICommon.Asset[] memory returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
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
    ILpStrategy.IncreaseLiquidityParams memory increaseParams = ILpStrategy.IncreaseLiquidityParams({
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.IncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    assets = new ICommon.Asset[](3);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });
    assets[2] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0 ether);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 77_577_661_546_568_449_798);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== decreasePosition ====");
    (, , , , , , , uint128 liquidity, , , , ) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityParams memory decreaseParams = ILpStrategy.DecreaseLiquidityParams({
      liquidity: liquidity / 2,
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidity),
      params: abi.encode(decreaseParams)
    });
    assets = new ICommon.Asset[](1);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 999_999_999_999_999_999);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 1_922_422_338_453_431_550_201);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);

    console.log("==== convertIntoExisting ====");
    ICommon.Asset memory existing = returnAssets[2];
    assets = new ICommon.Asset[](2);
    assets[0] = returnAssets[0];
    assets[1] = returnAssets[1];

    transferAssets(assets, address(lpStrategy));
    IERC721(NFPM).transferFrom(USER, address(lpStrategy), existing.tokenId);
    returnAssets = lpStrategy.convertIntoExisting(existing, assets);
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 1928);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
  }

  function test_LpStrategyMintValidate() public {
    console.log("==== test_LpStrategyMintValidation ====");
    ICommon.Asset[] memory assets = new ICommon.Asset[](1);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
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
    lpStrategy.convert(assets, 0, abi.encode(instruction));

    assets = new ICommon.Asset[](2);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
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
    lpStrategy.convert(assets, 0, abi.encode(instruction));
  }

  function test_lpStrategyIncreaseValidate() public {
    console.log("==== test_lpStrategyIncreaseValidate ====");
    ICommon.Asset[] memory assets = new ICommon.Asset[](2);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
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
    lpStrategy.convert(assets, 0, abi.encode(instruction));
    ILpStrategy.IncreaseLiquidityParams memory increaseParams = ILpStrategy.IncreaseLiquidityParams({
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.IncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, 0, abi.encode(instruction));
  }

  function test_LpStrategyDecreaseValidate() public {
    ICommon.Asset[] memory assets = new ICommon.Asset[](2);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
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
    ICommon.Asset[] memory returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
    (, , , , , , , uint128 liquidity, , , , ) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityParams memory decreaseParams = ILpStrategy.DecreaseLiquidityParams({
      liquidity: liquidity + 1,
      amount0Min: 0,
      amount1Min: 0
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidity),
      params: abi.encode(decreaseParams)
    });
    assets = new ICommon.Asset[](1);
    assets[0] = returnAssets[2];
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, 0, abi.encode(instruction));
  }

  function test_LpStrategyOptimalSwap() public {
    console.log("==== test_LpStrategyOptimalSwap ====");

    ICommon.Asset[] memory assets = new ICommon.Asset[](1);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
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
    ICommon.Asset[] memory returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
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
    ILpStrategy.SwapAndIncreaseLiquidityParams memory increaseParams = ILpStrategy.SwapAndIncreaseLiquidityParams({
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndIncreaseLiquidity),
      params: abi.encode(increaseParams)
    });
    assets = new ICommon.Asset[](2);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 340_659_039);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
    console.log("==== decreasePositionAndSwap ====");
    (, , , , , , , uint128 liquidity, , , , ) = INFPM(NFPM).positions(returnAssets[2].tokenId);
    ILpStrategy.DecreaseLiquidityAndSwapParams memory decreaseParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
      liquidity: liquidity / 2,
      amount0Min: 0,
      amount1Min: 0,
      principleAmountOutMin: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      params: abi.encode(decreaseParams)
    });
    assets = new ICommon.Asset[](1);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC721,
      strategy: address(lpStrategy),
      token: NFPM,
      tokenId: returnAssets[2].tokenId,
      amount: 1
    });
    transferAssets(assets, address(lpStrategy));
    returnAssets = lpStrategy.convert(assets, 0, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1_499_264_824_966_661_098);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(returnAssets[2].tokenId), USER);
  }
}
