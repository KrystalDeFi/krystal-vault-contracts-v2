// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { TestCommon, IV3SwapRouter, WETH, DAI, USER, USDC, NFPM, PLATFORM_WALLET } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/public-vault/core/VaultFactory.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/public-vault/strategies/lpUniV3/LpStrategy.sol";
import { LpChainingStrategy } from "../../contracts/public-vault/strategies/lpChaining/LpChainingStrategy.sol";
import { LpValidator } from "../../contracts/public-vault/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/public-vault/interfaces/strategies/ILpStrategy.sol";
import { ILpChainingStrategy } from
  "../../contracts/public-vault/interfaces/strategies/lpChaining/ILpChainingStrategy.sol";
import { ILpValidator } from "../../contracts/public-vault/interfaces/strategies/ILpValidator.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

contract LpChainingStrategyTest is TestCommon {
  LpStrategy public lpStrategy;
  LpChainingStrategy public lpChainingStrategy;
  IV3SwapRouter public v3SwapRouter;
  ICommon.VaultConfig public vaultConfig;
  ICommon.FeeConfig public feeConfig;
  PoolOptimalSwapper public swapper;
  LpValidator public validator;
  Vault public vaultImplementation;
  VaultFactory public vaultFactory;
  Vault public vaultInstance;
  uint256 currentBlock;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);
    currentBlock = block.number;
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

    address[] memory whitelistAutomator = new address[](0);
    // whitelistAutomator[0] = USER;

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
    address[] memory whitelistNfpms = new address[](1);
    whitelistNfpms[0] = address(NFPM);

    validator = new LpValidator();
    validator.initialize(USER, address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));
    lpChainingStrategy = new LpChainingStrategy(address(configManager));
    vaultConfig = ICommon.VaultConfig({
      principalToken: WETH,
      allowDeposit: false,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      supportedAddresses: new address[](0)
    });
    address[] memory strategies = new address[](2);
    strategies[0] = address(lpStrategy);
    strategies[1] = address(lpChainingStrategy);
    configManager.whitelistStrategy(strategies, true);

    // Set up VaultFactory
    vaultImplementation = new Vault();
    vaultFactory = new VaultFactory();
    vaultFactory.initialize(USER, WETH, address(configManager), address(vaultImplementation));

    // User can create a Vault without any assets
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 0,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    address vaultAddress = vaultFactory.createVault(params);

    vaultInstance = Vault(payable(vaultAddress));

    IERC20(WETH).approve(address(vaultInstance), 100 ether);
    vaultInstance.deposit(4 ether, 0);
  }

  // Helper to mint a position and return the NFT asset
  function _mintPositions() internal {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndMintPositionParams({
          nfpm: INFPM(NFPM),
          token0: WETH,
          token1: USDC,
          fee: 500,
          tickLower: -887_220,
          tickUpper: 887_200,
          amount0Min: 0,
          amount1Min: 0,
          swapData: ""
        })
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndMintPositionParams({
          nfpm: INFPM(NFPM),
          token0: WETH,
          token1: USDC,
          fee: 500,
          tickLower: -887_220,
          tickUpper: 887_200,
          amount0Min: 0,
          amount1Min: 0,
          swapData: ""
        })
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vm.roll(++currentBlock);
  }

  // Helper to mint a position and return the NFT asset
  function _mint3Positions() internal {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](3);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    assets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1 ether);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndMintPositionParams({
          nfpm: INFPM(NFPM),
          token0: WETH,
          token1: USDC,
          fee: 500,
          tickLower: -887_220,
          tickUpper: 887_200,
          amount0Min: 0,
          amount1Min: 0,
          swapData: ""
        })
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndMintPositionParams({
          nfpm: INFPM(NFPM),
          token0: WETH,
          token1: USDC,
          fee: 500,
          tickLower: -887_220,
          tickUpper: 887_200,
          amount0Min: 0,
          amount1Min: 0,
          swapData: ""
        })
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndMintPositionParams({
          nfpm: INFPM(NFPM),
          token0: WETH,
          token1: USDC,
          fee: 500,
          tickLower: -887_220,
          tickUpper: 887_200,
          amount0Min: 0,
          amount1Min: 0,
          swapData: ""
        })
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vm.roll(++currentBlock);
  }

  function test_batchMintPosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3, "Should have principal token and 2 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 4 ether - 1.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1 ether, TOLERANCE);
  }

  function test_batchIncreasePosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](4);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[1] = vaultAssets[1];
    assets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[3] = vaultAssets[2];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3, "Should have principal token and 2 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 4 ether - 2.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 1 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1.5 ether, TOLERANCE);
  }

  function test_batchDecreasePosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = vaultAssets[1];
    assets[1] = vaultAssets[2];
    (,,,,,,, uint128 liquidity1,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
    (,,,,,,, uint128 liquidity2,,,,) = INFPM(NFPM).positions(vaultAssets[2].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity1 / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity2 / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3);
    assertApproxEqRel(vaultAssets[0].amount, 4 ether - 1.5 ether + 1.5 ether / 2, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.25 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 0.5 ether, TOLERANCE);
  }

  function test_batchDecreasePosition_fail_invalidInstruction() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = vaultAssets[1];
    assets[1] = vaultAssets[2];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vm.expectRevert();
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
  }

  function test_batchRebalancePosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = vaultAssets[1];
    assets[1] = vaultAssets[2];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndRebalancePosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndRebalancePositionParams({
          tickLower: -443_580,
          tickUpper: 443_580,
          decreasedAmount0Min: 0,
          decreasedAmount1Min: 0,
          amount0Min: 0,
          amount1Min: 0,
          compoundFee: true,
          compoundFeeAmountOutMin: 0,
          swapData: ""
        })
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndRebalancePosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndRebalancePositionParams({
          tickLower: -443_580,
          tickUpper: 443_580,
          decreasedAmount0Min: 0,
          decreasedAmount1Min: 0,
          amount0Min: 0,
          amount1Min: 0,
          compoundFee: true,
          compoundFeeAmountOutMin: 0,
          swapData: ""
        })
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3, "Should have principal token and 2 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 4 ether - 1.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1 ether, TOLERANCE);
  }

  function test_batchRebalancePosition_fail_invalidInstruction() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = vaultAssets[1];
    assets[1] = vaultAssets[2];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.DecreaseLiquidityAndSwapParams({
          liquidity: 1,
          amount0Min: 0,
          amount1Min: 0,
          principalAmountOutMin: 0,
          swapData: ""
        })
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndRebalancePosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndRebalancePositionParams({
          tickLower: -887_220,
          tickUpper: 887_200,
          decreasedAmount0Min: 0,
          decreasedAmount1Min: 0,
          amount0Min: 0,
          amount1Min: 0,
          compoundFee: false,
          compoundFeeAmountOutMin: 0,
          swapData: ""
        })
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vm.expectRevert();
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
  }

  function test_batchCompoundPosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = vaultAssets[1];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](1);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndCompound,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3, "Should have principal token and 2 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 4 ether - 1.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 1 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 0.5 ether, TOLERANCE);
  }

  function test_batchCompoundPosition_fail_invalidInstruction() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = vaultAssets[1];
    assets[1] = vaultAssets[2];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.DecreaseLiquidityAndSwapParams({
          liquidity: 1,
          amount0Min: 0,
          amount1Min: 0,
          principalAmountOutMin: 0,
          swapData: ""
        })
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndCompound,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndCompoundParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vm.expectRevert();
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
  }

  function test_mintIncreaseRebalancePosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](4);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[2] = vaultAssets[1];
    assets[3] = vaultAssets[2];
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndMintPositionParams({
          nfpm: INFPM(NFPM),
          token0: WETH,
          token1: USDC,
          fee: 500,
          tickLower: -887_220,
          tickUpper: 887_200,
          amount0Min: 0,
          amount1Min: 0,
          swapData: ""
        })
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndRebalancePosition,
      address(lpStrategy),
      abi.encode(
        ILpStrategy.SwapAndRebalancePositionParams({
          tickLower: -443_580,
          tickUpper: 443_580,
          decreasedAmount0Min: 0,
          decreasedAmount1Min: 0,
          amount0Min: 0,
          amount1Min: 0,
          compoundFee: true,
          compoundFeeAmountOutMin: 0,
          swapData: ""
        })
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.Batch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 4, "Should have principal token and 3 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 4 ether - 2.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 1 ether, TOLERANCE);
  }

  function test_decreaseIncreasePosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](3);
    assets[0] = vaultAssets[1];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 2.5 ether);
    assets[2] = vaultAssets[2];
    (,,,,,,, uint128 liquidity1,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity1 / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3, "Should have principal token and 3 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 0.0000787 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.25 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 3.75 ether, TOLERANCE);
  }

  function test_decreaseBatchIncreasePosition() public {
    _mint3Positions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](5);
    assets[0] = vaultAssets[1];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[2] = vaultAssets[2];
    assets[3] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[4] = vaultAssets[3];
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 4, "Should have principal token and 3 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 0.000165 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1.75 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 1.75 ether, TOLERANCE);
  }

  function test_decreaseBatchIncreasePosition2() public {
    _mint3Positions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](5);
    assets[0] = vaultAssets[1];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1);
    assets[2] = vaultAssets[2];
    assets[3] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1);
    assets[4] = vaultAssets[3];
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 4, "Should have principal token and 3 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 1 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1.25 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 1.25 ether, TOLERANCE);
  }

  function test_decreaseBatchIncreasePosition3() public {
    _mint3Positions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](5);
    assets[0] = vaultAssets[1];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[2] = vaultAssets[2];
    assets[3] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[4] = vaultAssets[3];
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0, abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndIncreaseLiquidity,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0, abi.encode(ILpStrategy.SwapAndIncreaseLiquidityParams({ amount0Min: 0, amount1Min: 0, swapData: "" }))
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 4, "Should have principal token and 3 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1.5 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 1.5 ether, TOLERANCE);
  }

  function test_batchDecreaseBatchMintPosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](3);
    assets[0] = vaultAssets[2];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[2].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(
            ILpStrategy.SwapAndMintPositionParams({
              nfpm: INFPM(NFPM),
              token0: WETH,
              token1: USDC,
              fee: 500,
              tickLower: -887_220,
              tickUpper: 887_200,
              amount0Min: 0,
              amount1Min: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(
            ILpStrategy.SwapAndMintPositionParams({
              nfpm: INFPM(NFPM),
              token0: WETH,
              token1: USDC,
              fee: 500,
              tickLower: -887_220,
              tickUpper: 887_200,
              amount0Min: 0,
              amount1Min: 0,
              swapData: ""
            })
          )
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 5, "Should have principal token and 4 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 1.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 0.75 ether, TOLERANCE);
    assertEq(vaultAssets[4].amount, 1);
    assertEq(vaultAssets[4].token, NFPM);
    assertEq(vaultAssets[4].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal4 = lpStrategy.valueOf(vaultAssets[4], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal4, 0.75 ether, TOLERANCE);
  }

  function test_batchDecreaseBatchMintPosition2() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](3);
    assets[0] = vaultAssets[2];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1);
    assets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 1);
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[2].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(
            ILpStrategy.SwapAndMintPositionParams({
              nfpm: INFPM(NFPM),
              token0: WETH,
              token1: USDC,
              fee: 500,
              tickLower: -887_220,
              tickUpper: 887_200,
              amount0Min: 0,
              amount1Min: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0.2498 ether,
          abi.encode(
            ILpStrategy.SwapAndMintPositionParams({
              nfpm: INFPM(NFPM),
              token0: WETH,
              token1: USDC,
              fee: 500,
              tickLower: -887_220,
              tickUpper: 887_200,
              amount0Min: 0,
              amount1Min: 0,
              swapData: ""
            })
          )
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 5, "Should have principal token and 4 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 2.5 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 0.25 ether, TOLERANCE);
    assertEq(vaultAssets[4].amount, 1);
    assertEq(vaultAssets[4].token, NFPM);
    assertEq(vaultAssets[4].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal4 = lpStrategy.valueOf(vaultAssets[4], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal4, 0.25 ether, TOLERANCE);
  }

  function test_batchDecreaseBatchMintPosition3() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](3);
    assets[0] = vaultAssets[2];
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    assets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    (,,,,,,, uint128 liquidity,,,,) = INFPM(NFPM).positions(vaultAssets[2].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](3);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.SwapAndMintPositionParams({
              nfpm: INFPM(NFPM),
              token0: WETH,
              token1: USDC,
              fee: 500,
              tickLower: -887_220,
              tickUpper: 887_200,
              amount0Min: 0,
              amount1Min: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[2] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndMintPosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.SwapAndMintPositionParams({
              nfpm: INFPM(NFPM),
              token0: WETH,
              token1: USDC,
              fee: 500,
              tickLower: -887_220,
              tickUpper: 887_200,
              amount0Min: 0,
              amount1Min: 0,
              swapData: ""
            })
          )
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 5, "Should have principal token and 4 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 2 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[3].amount, 1);
    assertEq(vaultAssets[3].token, NFPM);
    assertEq(vaultAssets[3].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal3 = lpStrategy.valueOf(vaultAssets[3], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal3, 0.5 ether, TOLERANCE);
    assertEq(vaultAssets[4].amount, 1);
    assertEq(vaultAssets[4].token, NFPM);
    assertEq(vaultAssets[4].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal4 = lpStrategy.valueOf(vaultAssets[4], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal4, 0.5 ether, TOLERANCE);
  }

  function test_batchDecreaseBatchRebalancePosition() public {
    _mintPositions();
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](2);
    assets[0] = vaultAssets[1];
    assets[1] = vaultAssets[2];
    (,,,,,,, uint128 liquidity1,,,,) = INFPM(NFPM).positions(vaultAssets[1].tokenId);
    ILpChainingStrategy.ChainingInstruction[] memory instructions = new ILpChainingStrategy.ChainingInstruction[](2);
    instructions[0] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.DecreaseLiquidityAndSwap,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.DecreaseLiquidityAndSwapParams({
              liquidity: liquidity1 / 2,
              amount0Min: 0,
              amount1Min: 0,
              principalAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    instructions[1] = ILpChainingStrategy.ChainingInstruction(
      ILpStrategy.InstructionType.SwapAndRebalancePosition,
      address(lpStrategy),
      abi.encode(
        ILpChainingStrategy.ModifiedAddonPrincipalAmountParams(
          0,
          abi.encode(
            ILpStrategy.SwapAndRebalancePositionParams({
              tickLower: -443_580,
              tickUpper: 443_580,
              decreasedAmount0Min: 0,
              decreasedAmount1Min: 0,
              amount0Min: 0,
              amount1Min: 0,
              compoundFee: false,
              compoundFeeAmountOutMin: 0,
              swapData: ""
            })
          )
        )
      )
    );
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpChainingStrategy.ChainingInstructionType.DecreaseAndBatch),
      params: abi.encode(instructions)
    });
    vaultInstance.allocate(assets, lpChainingStrategy, 0, abi.encode(instruction));
    vaultAssets = vaultInstance.getInventory();
    assertEq(vaultAssets.length, 3, "Should have principal token and 3 NFT assets in vault");
    assertApproxEqRel(vaultAssets[0].amount, 2.75 ether, TOLERANCE);
    assertEq(vaultAssets[0].token, WETH);
    assertEq(vaultAssets[0].tokenId, 0);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].token, NFPM);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal1 = lpStrategy.valueOf(vaultAssets[1], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal1, 0.25 ether, TOLERANCE);
    assertEq(vaultAssets[2].amount, 1);
    assertEq(vaultAssets[2].token, NFPM);
    assertEq(vaultAssets[2].strategy, address(lpStrategy));
    uint256 valueOfPositionInPrincipal2 = lpStrategy.valueOf(vaultAssets[2], WETH);
    assertApproxEqRel(valueOfPositionInPrincipal2, 1 ether, TOLERANCE);
  }
}
