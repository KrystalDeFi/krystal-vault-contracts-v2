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
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";

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
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    ConfigManager configManager = new ConfigManager();
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
    LpValidator validator = new LpValidator(address(configManager));
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(swapper), address(validator), address(lpFeeTaker));
    vaultConfig = ICommon.VaultConfig({
      principalToken: WETH,
      allowDeposit: false,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      supportedAddresses: new address[](0)
    });
  }

  function test_LpStrategyRebalanceValidate() public {
    console.log("==== test_LpStrategyRebalanceValidate ====");
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
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));

    ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
      tickLower: -887_220,
      tickUpper: 887_220,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0,
      compoundFee: false,
      compoundFeeAmountOutMin: 0,
      swapData: ""
    });
    instruction = ICommon.Instruction({ instructionType: type(uint8).max, params: abi.encode(rebalanceParams) });
    transferAssets(assets, address(lpStrategy));
    vm.expectRevert();
    lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
  }

  function test_LpStrategyCompoundValidate() public {
    console.log("==== test_LpStrategyCompoundValidate ====");
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
    console.log("swapAndMint instruction %s");
    console.logBytes(abi.encode(instruction));
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
    transferAsset(assets[0], address(lpStrategy));

    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 340_659_039);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);

    console.log("==== swapAndRebalancePosition ====");
    ILpStrategy.SwapAndRebalancePositionParams memory rebalanceParams = ILpStrategy.SwapAndRebalancePositionParams({
      tickLower: -443_580,
      tickUpper: 443_580,
      decreasedAmount0Min: 0,
      decreasedAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0,
      compoundFee: true,
      compoundFeeAmountOutMin: 0,
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

    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 4);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1864);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 1);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
    assertEq(returnAssets[3].token, NFPM);
    assertEq(returnAssets[3].amount, 1);
    assertEq(returnAssets[3].tokenId, assets[0].tokenId);
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

    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);

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

    returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 1_499_264_827_661_936_896);
    assertEq(returnAssets[1].token, USDC);
    assertEq(returnAssets[1].amount, 0);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
  }

  function test_LpStrategyFeeTaker() public {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    AssetLib.Asset[] memory returnAssets;

    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(WETH, DAI, 3000);
    address mockVaultOwner = address(0x100);
    address mockPlatformWallet = address(0x200);
    address mockGasFeeRecipient = address(0x300);
    {
      IUniswapV3Pool(pool).increaseObservationCardinalityNext(3);
      skip(100);
    }

    ICommon.FeeConfig memory publicFeeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 500,
      vaultOwner: mockVaultOwner,
      platformFeeBasisPoint: 1000,
      platformFeeRecipient: mockPlatformWallet,
      gasFeeX64: uint64(uint256((1500 * 2 ** 64)) / 10_000),
      gasFeeRecipient: mockGasFeeRecipient
    });

    {
      console.log("==== swapAndMintPosition ====");
      assets[0] = AssetLib.Asset({
        assetType: AssetLib.AssetType.ERC20,
        strategy: address(0),
        token: WETH,
        tokenId: 0,
        amount: 2 ether
      });

      ILpStrategy.SwapAndMintPositionParams memory mintParams = ILpStrategy.SwapAndMintPositionParams({
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
        params: abi.encode(mintParams)
      });
      transferAssets(assets, address(lpStrategy));
      returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
      skip(100);

      IERC20(WETH).approve(address(swapper), 1 ether);
      (uint256 amountOut,) = swapper.poolSwap(pool, 1 ether, true, 0, "");
      skip(100);

      IERC20(DAI).approve(address(swapper), amountOut);
      swapper.poolSwap(pool, amountOut - 1 ether, false, 0, "");
      skip(100);
      swapper.poolSwap(pool, 1 ether, false, 0, "");
      skip(100);

      // uint256 fee0 = 2_556_795_487_525_688;
      // uint256 fee1 = 2_651_766_154_928_366_678;

      console.log("==== test take fee when harvest ====");

      returnAssets = lpStrategy.harvest(returnAssets[2], WETH, 0, vaultConfig, publicFeeConfig);

      assertEq(returnAssets.length, 3);
      assertEq(IERC20(WETH).balanceOf(mockVaultOwner), 216_203_259_418_342, "owner fee mismatch");
      assertEq(IERC20(DAI).balanceOf(mockVaultOwner), 0);
      assertEq(IERC20(WETH).balanceOf(mockPlatformWallet), 432_406_518_836_685, "platform fee mismatch");
      assertEq(IERC20(DAI).balanceOf(mockPlatformWallet), 0);
      assertEq(IERC20(WETH).balanceOf(mockGasFeeRecipient), 648_609_778_255_028, "gasFee mismatch");
      assertEq(IERC20(DAI).balanceOf(mockGasFeeRecipient), 0);
      assertEq(returnAssets[0].amount, 3_026_845_631_856_802, "amount0 mismatch");
      assertEq(returnAssets[1].amount, 0);
    }

    {
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
      (uint256 amountOut,) = swapper.poolSwap(pool, 1 ether, true, 0, "");
      IERC20(DAI).approve(address(swapper), amountOut);
      swapper.poolSwap(pool, amountOut, false, 0, "");
      lpStrategy.valueOf(returnAssets[2], WETH);

      ILpStrategy.SwapAndCompoundParams memory compoundParams =
        ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" });
      ICommon.Instruction memory instruction = ICommon.Instruction({
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

      returnAssets = lpStrategy.convert(assets, vaultConfig, publicFeeConfig, abi.encode(instruction));

      // uint256 fee0 = 2_601_269_379_622_417;
      // uint256 fee1 = 243_296_432_368_259_167;
      assertEq(IERC20(WETH).balanceOf(mockVaultOwner), 216_483_721_965_001, "vault owner fee 0"); // fee0 * 500 / 10_000
      assertEq(IERC20(DAI).balanceOf(mockVaultOwner), 0, "vault owner fee 1"); // fee1 * 500 /
      // 10_000
      assertEq(IERC20(WETH).balanceOf(mockPlatformWallet), 432_967_443_930_004, "platform fee 0"); // fee0 * 1000 /
      // 10_000
      assertEq(IERC20(DAI).balanceOf(mockPlatformWallet), 0, "platform fee 1"); // fee1 * 1000 /
      // 10_000
      assertEq(IERC20(WETH).balanceOf(mockGasFeeRecipient), 649_451_165_895_007, "gas fee 0"); // fee0 * 1500 / 10_000
      assertEq(IERC20(DAI).balanceOf(mockGasFeeRecipient), 0, "gas fee 1"); // fee1 * 1500 / 10_000
    }

    {
      console.log("==== test take fee when decrease liquidity ====");
      setErc20Balance(WETH, mockVaultOwner, 0);
      setErc20Balance(DAI, mockVaultOwner, 0);
      setErc20Balance(WETH, mockPlatformWallet, 0);
      setErc20Balance(DAI, mockPlatformWallet, 0);
      setErc20Balance(WETH, mockGasFeeRecipient, 0);
      setErc20Balance(DAI, mockGasFeeRecipient, 0);

      // do another swap to generate fee
      IERC20(WETH).approve(address(swapper), 1 ether);
      (uint256 amountOut,) = swapper.poolSwap(pool, 1 ether, true, 0, "");
      IERC20(DAI).approve(address(swapper), amountOut);
      swapper.poolSwap(pool, amountOut, false, 0, "");
      lpStrategy.valueOf(returnAssets[2], WETH);

      console.log("==== decreasePosition ====");
      (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(returnAssets[2].tokenId);
      ILpStrategy.DecreaseLiquidityAndSwapParams memory decreaseParams = ILpStrategy.DecreaseLiquidityAndSwapParams({
        liquidity: liquidity / 2,
        amount0Min: 0,
        amount1Min: 0,
        principalAmountOutMin: 0,
        swapData: ""
      });
      ICommon.Instruction memory instruction = ICommon.Instruction({
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

      returnAssets = lpStrategy.convert(assets, vaultConfig, publicFeeConfig, abi.encode(instruction));

      assertEq(IERC20(WETH).balanceOf(mockVaultOwner), 216_439_552_697_973, "vault owner fee 0");
      assertEq(IERC20(DAI).balanceOf(mockVaultOwner), 0, "vault owner fee 1");
      assertEq(IERC20(WETH).balanceOf(mockPlatformWallet), 432_879_105_395_949, "platform fee 0");
      assertEq(IERC20(DAI).balanceOf(mockPlatformWallet), 0, "platform fee 1");
      assertEq(IERC20(WETH).balanceOf(mockGasFeeRecipient), 649_318_658_093_924, "gas fee 0");
      assertEq(IERC20(DAI).balanceOf(mockGasFeeRecipient), 0, "gas fee 1");
    }
  }

  function test_LpStrategyPriceSanityCheck() public {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    AssetLib.Asset[] memory returnAssets;

    address pool = IUniswapV3Factory(INFPM(NFPM).factory()).getPool(WETH, DAI, 3000);
    address mockVaultOwner = address(0x100);
    address mockPlatformWallet = address(0x200);
    address mockGasFeeRecipient = address(0x300);
    {
      IUniswapV3Pool(pool).increaseObservationCardinalityNext(3);
      skip(100);
      vm.roll(block.number + 1);
    }

    ICommon.FeeConfig memory publicFeeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 500,
      vaultOwner: mockVaultOwner,
      platformFeeBasisPoint: 1000,
      platformFeeRecipient: mockPlatformWallet,
      gasFeeX64: uint64(uint256((1500 * 2 ** 64)) / 10_000),
      gasFeeRecipient: mockGasFeeRecipient
    });

    {
      console.log("==== swapAndMintPosition ====");
      assets[0] = AssetLib.Asset({
        assetType: AssetLib.AssetType.ERC20,
        strategy: address(0),
        token: WETH,
        tokenId: 0,
        amount: 2 ether
      });

      ILpStrategy.SwapAndMintPositionParams memory mintParams = ILpStrategy.SwapAndMintPositionParams({
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
        params: abi.encode(mintParams)
      });
      console.log("==== allocate normally ====");
      transferAssets(assets, address(lpStrategy));
      returnAssets = lpStrategy.convert(assets, vaultConfig, feeConfig, abi.encode(instruction));
      skip(100);
      vm.roll(block.number + 1);
      int24 tick;
      (, tick,,,,,) = IUniswapV3Pool(pool).slot0();
      console.log("==== tick before price surge %s ====", tick);
      console.log("==== swap 20_000 DAI to WETH to surge the price ====");

      // swap a very large amount to drive the price up
      IERC20(DAI).approve(address(swapper), 20_000 ether);
      swapper.poolSwap(pool, 20_000 ether, false, 0, "");
      vm.roll(block.number + 1);
      console.log("==== tick after price surge %s ====", tick);

      console.log("==== cannot harvest because price surge pass 5% ====");
      vm.expectRevert(ILpValidator.PriceSanityCheckFailed.selector);
      returnAssets = lpStrategy.harvest(
        returnAssets[2],
        WETH,
        0,
        ICommon.VaultConfig({
          principalToken: WETH,
          allowDeposit: true,
          rangeStrategyType: 0,
          tvlStrategyType: 0,
          supportedAddresses: new address[](0)
        }),
        publicFeeConfig
      );
    }
  }
}
