// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, PANCAKE_NFPM as NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// Private Vault contracts
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateVaultFactory } from "../../contracts/private-vault/core/PrivateVaultFactory.sol";
import { IPrivateVaultFactory } from "../../contracts/private-vault/interfaces/core/IPrivateVaultFactory.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateConfigManager } from "../../contracts/private-vault/interfaces/core/IPrivateConfigManager.sol";

// V3Utils Strategy contracts
import { V3UtilsV2Strategy as V3UtilsStrategy } from
  "../../contracts/private-vault/strategies/lpv3/V3UtilsV2Strategy.sol";
import { IV3UtilsV2 as IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3UtilsV2.sol";

contract PrivateVaultIntegrationTest is TestCommon, IERC721Receiver {
  // Test constants
  address constant V3_UTILS = 0x16c6346916EEF89FD2C2Fb7DA61dA8825948Ec93; // V3Utils contract on Base
  address constant SWAP_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14; // Pancake V3 SwapRouter on Base
  uint24 constant FEE_TIER = 100; // 0.01% fee tier
  int24 constant TICK_SPACING = 1;
  int24 constant TICK_LOWER = -887_000;
  int24 constant TICK_UPPER = 887_000;

  // Contract instances
  PrivateConfigManager public configManager;
  PrivateVaultFactory public vaultFactory;
  PrivateVault public vaultImplementation;
  V3UtilsStrategy public v3UtilsStrategy;
  PrivateVault public vaultInstance;

  // Test addresses
  address public vaultOwner = USER;
  address public admin = 0x1234567890123456789012345678901234567891;

  function setUp() public {
    // Create mainnet fork for consistent testing environment
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 28_445_596);
    vm.selectFork(fork);

    vm.startPrank(vaultOwner);

    // Set up test token balances
    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 100_000 * 1e6);
    vm.deal(vaultOwner, 100 ether);

    // Deploy PrivateConfigManager
    address[] memory whitelistAdmins = new address[](1);
    whitelistAdmins[0] = admin;

    address[] memory whitelistStrategies = new address[](0); // Will add later
    address[] memory whitelistOwners = new address[](1);
    whitelistOwners[0] = vaultOwner;

    configManager = new PrivateConfigManager();
    configManager.initialize(
      admin, // owner
      whitelistStrategies,
      whitelistOwners
    );

    // Deploy V3UtilsStrategy
    v3UtilsStrategy = new V3UtilsStrategy(V3_UTILS);

    // Add V3UtilsStrategy to whitelist
    address[] memory strategiesToAdd = new address[](1);
    strategiesToAdd[0] = address(v3UtilsStrategy);
    vm.stopPrank();

    vm.prank(admin);
    configManager.setWhitelistTargets(strategiesToAdd, true);

    vm.startPrank(vaultOwner);

    // Deploy PrivateVault implementation
    vaultImplementation = new PrivateVault();

    // Deploy PrivateVaultFactory
    vaultFactory = new PrivateVaultFactory();
    vaultFactory.initialize(admin, address(configManager), address(vaultImplementation));

    // Create a vault instance
    vaultInstance = PrivateVault(payable(vaultFactory.createVault("random")));

    vm.stopPrank();
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  // Helper function to create multicall data
  function _createMulticallData(address target, bytes memory data)
    internal
    pure
    returns (address[] memory targets, bytes[] memory dataArray, IPrivateCommon.CallType[] memory callTypes)
  {
    targets = new address[](1);
    dataArray = new bytes[](1);
    callTypes = new IPrivateCommon.CallType[](1);

    targets[0] = target;
    dataArray[0] = data;
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;
  }

  // Helper function to deposit tokens (no prank management)
  function _depositTokens(uint256 wethAmount, uint256 usdcAmount) internal {
    IERC20(WETH).transfer(address(vaultInstance), wethAmount);
    IERC20(USDC).transfer(address(vaultInstance), usdcAmount);
  }

  // Helper function to create LP position (no prank management)
  function _createLPPosition(uint256 wethAmount, uint256 usdcAmount) internal returns (uint256 tokenId) {
    // Deposit tokens to vault first
    _depositTokens(wethAmount, usdcAmount);

    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = wethAmount;
    amounts[1] = usdcAmount;

    // Prepare swapAndMint parameters
    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0, // UNI_V3
      nfpm: NFPM,
      token0: WETH < USDC ? WETH : USDC,
      token1: WETH < USDC ? USDC : WETH,
      fee: FEE_TIER,
      tickSpacing: TICK_SPACING,
      tickLower: TICK_LOWER,
      tickUpper: TICK_UPPER,
      protocolFeeX64: 0,
      amount0: WETH < USDC ? wethAmount / 2 : usdcAmount / 2,
      amount1: WETH < USDC ? usdcAmount / 2 : wethAmount / 2,
      amount2: 0,
      recipient: address(vaultInstance),
      deadline: block.timestamp + 300,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0
    });

    // Prepare strategy call data
    bytes memory strategyCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndMint.selector,
      params,
      0 ether, // ethValue
      tokens,
      amounts
    );

    (address[] memory targets, bytes[] memory dataArray, IPrivateCommon.CallType[] memory callTypes) =
      _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute strategy through vault multicall
    vaultInstance.multicall(targets, dataArray, callTypes);

    // Return the token ID of the created position
    return INFPM(NFPM).tokenOfOwnerByIndex(address(vaultInstance), 0);
  }

  // Helper function to add liquidity to existing position (no prank management)
  function _addLiquidityToPosition(uint256 tokenId, uint256 wethAmount, uint256 usdcAmount) internal {
    // Deposit more tokens
    _depositTokens(wethAmount, usdcAmount);

    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = wethAmount;
    amounts[1] = usdcAmount;

    // Get position info
    (,, address token0,,,,, uint128 liquidityBefore,,,,) = INFPM(NFPM).positions(tokenId);

    // Prepare swapAndIncreaseLiquidity parameters
    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0, // UNI_V3
      nfpm: NFPM,
      tokenId: tokenId,
      amount0: token0 == WETH ? wethAmount / 2 : usdcAmount / 2,
      amount1: token0 == WETH ? usdcAmount / 2 : wethAmount / 2,
      amount2: 0,
      recipient: address(vaultInstance),
      deadline: block.timestamp + 300,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      protocolFeeX64: 0
    });

    // Prepare strategy call data
    bytes memory strategyCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndIncreaseLiquidity.selector,
      params,
      0 ether, // ethValue
      tokens,
      amounts
    );

    (address[] memory targets, bytes[] memory dataArray, IPrivateCommon.CallType[] memory callTypes) =
      _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute strategy through vault multicall
    vaultInstance.multicall(targets, dataArray, callTypes);
  }

  // Helper function to simulate swaps and generate fees (no prank management)
  function _simulateSwapsToGenerateFees(address token0, address token1, uint24 fee) internal {
    // Create a large trader account with significant balances
    address trader = 0x5555555555555555555555555555555555555555;

    // Set up trader with large balances
    setErc20Balance(token0, trader, 1000 ether);
    setErc20Balance(token1, trader, 1_000_000 * 1e6); // Assuming token1 might be USDC

    vm.startPrank(trader);

    // Approve router for swaps
    IERC20(token0).approve(SWAP_ROUTER, type(uint256).max);
    IERC20(token1).approve(SWAP_ROUTER, type(uint256).max);

    ISwapRouter swapRouter = ISwapRouter(SWAP_ROUTER);

    // Perform multiple swaps in both directions to generate fees
    for (uint256 i = 0; i < 5; i++) {
      // Swap token0 for token1
      ISwapRouter.ExactInputSingleParams memory params0to1 = ISwapRouter.ExactInputSingleParams({
        tokenIn: token0,
        tokenOut: token1,
        fee: fee,
        recipient: trader,
        deadline: block.timestamp + 300,
        amountIn: 10 ether, // 10 units of token0
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });

      swapRouter.exactInputSingle(params0to1);

      // Swap token1 for token0
      ISwapRouter.ExactInputSingleParams memory params1to0 = ISwapRouter.ExactInputSingleParams({
        tokenIn: token1,
        tokenOut: token0,
        fee: fee,
        recipient: trader,
        deadline: block.timestamp + 300,
        amountIn: 25_000 * 1e6, // Assuming token1 is USDC with 6 decimals
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });

      swapRouter.exactInputSingle(params1to0);
    }

    vm.stopPrank();
  }

  // Helper function to transfer NFT and execute instructions (no prank management)
  function _transferAndExecuteNFT(uint256 tokenId) internal {
    // Prepare instructions for V3Utils execute
    IV3Utils.Instructions memory instructions = IV3Utils.Instructions({
      whatToDo: IV3Utils.WhatToDo.COMPOUND_FEES,
      protocol: 0,
      targetToken: address(0),
      amountRemoveMin0: 0,
      amountRemoveMin1: 0,
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      tickLower: 0,
      tickUpper: 0,
      compoundFees: true,
      liquidity: 0,
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp + 300,
      recipient: address(vaultInstance),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0
    });

    bytes memory encodedInstructions = abi.encode(instructions);

    // Prepare safeTransferNft call data
    bytes memory strategyCallData =
      abi.encodeWithSelector(V3UtilsStrategy.safeTransferNft.selector, NFPM, tokenId, encodedInstructions);

    (address[] memory targets, bytes[] memory dataArray, IPrivateCommon.CallType[] memory callTypes) =
      _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute strategy through vault multicall
    vaultInstance.multicall(targets, dataArray, callTypes);
  }

  // Test basic token deposit functionality
  function test_DepositTokens() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;

    uint256 vaultWethBefore = IERC20(WETH).balanceOf(address(vaultInstance));
    uint256 vaultUsdcBefore = IERC20(USDC).balanceOf(address(vaultInstance));

    _depositTokens(wethAmount, usdcAmount);

    uint256 vaultWethAfter = IERC20(WETH).balanceOf(address(vaultInstance));
    uint256 vaultUsdcAfter = IERC20(USDC).balanceOf(address(vaultInstance));

    assertEq(vaultWethAfter - vaultWethBefore, wethAmount);
    assertEq(vaultUsdcAfter - vaultUsdcBefore, usdcAmount);

    vm.stopPrank();
  }

  // Test V3UtilsStrategy swapAndMint functionality
  function test_V3UtilsStrategy_SwapAndMint() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;

    // Record NFT count before
    uint256 nftCountBefore = IERC721(NFPM).balanceOf(address(vaultInstance));

    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);

    // Verify NFT was received
    uint256 nftCountAfter = IERC721(NFPM).balanceOf(address(vaultInstance));
    assertEq(nftCountAfter, nftCountBefore + 1);

    // Verify the token ID is valid
    assertGt(tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test V3UtilsStrategy swapAndIncreaseLiquidity functionality
  function test_V3UtilsStrategy_SwapAndIncreaseLiquidity() public {
    vm.startPrank(vaultOwner);

    // First create a position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);

    // Get position info before increase
    (,,,,,,, uint128 liquidityBefore,,,,) = INFPM(NFPM).positions(tokenId);

    // Add more liquidity
    uint256 additionalWethAmount = 0.5 ether;
    uint256 additionalUsdcAmount = 1500 * 1e6;
    _addLiquidityToPosition(tokenId, additionalWethAmount, additionalUsdcAmount);

    // Verify liquidity increased
    (,,,,,,, uint128 liquidityAfter,,,,) = INFPM(NFPM).positions(tokenId);
    assertGt(liquidityAfter, liquidityBefore);

    vm.stopPrank();
  }

  // Test NFT transfer functionality
  function test_V3UtilsStrategy_SafeTransferNft() public {
    vm.startPrank(vaultOwner);

    // Create a position first
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);

    // Verify NFT is in vault before
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();

    // Simulate swaps to generate fees (needs its own prank management)
    address token0 = WETH < USDC ? WETH : USDC;
    address token1 = WETH < USDC ? USDC : WETH;
    _simulateSwapsToGenerateFees(token0, token1, FEE_TIER);

    vm.startPrank(vaultOwner);

    // Execute NFT transfer and processing
    _transferAndExecuteNFT(tokenId);

    // NFT should be returned to vault after processing
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test access control - only vault owner can execute strategies
  function test_AccessControl_OnlyOwnerCanExecute() public {
    address unauthorized = 0x9999999999999999999999999999999999999999;

    vm.startPrank(unauthorized);

    bytes memory strategyCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndMint.selector,
      IV3Utils.SwapAndMintParams({
        protocol: 0,
        nfpm: NFPM,
        token0: WETH,
        token1: USDC,
        fee: FEE_TIER,
        tickSpacing: TICK_SPACING,
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        protocolFeeX64: 0,
        amount0: 1 ether,
        amount1: 3000 * 1e6,
        amount2: 0,
        recipient: address(vaultInstance),
        deadline: block.timestamp + 300,
        swapSourceToken: address(0),
        amountIn0: 0,
        amountOut0Min: 0,
        swapData0: "",
        amountIn1: 0,
        amountOut1Min: 0,
        swapData1: "",
        amountAddMin0: 0,
        amountAddMin1: 0
      }),
      0 ether,
      new address[](0),
      new uint256[](0)
    );

    (address[] memory targets, bytes[] memory dataArray, IPrivateCommon.CallType[] memory callTypes) =
      _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // This should revert due to access control
    vm.expectRevert();
    vaultInstance.multicall(targets, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test error handling for non-whitelisted strategy
  function test_ErrorHandling_NonWhitelistedStrategy() public {
    vm.startPrank(vaultOwner);

    // Deploy a non-whitelisted strategy
    V3UtilsStrategy nonWhitelistedStrategy = new V3UtilsStrategy(V3_UTILS);

    bytes memory strategyCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndMint.selector,
      IV3Utils.SwapAndMintParams({
        protocol: 0,
        nfpm: NFPM,
        token0: WETH,
        token1: USDC,
        fee: FEE_TIER,
        tickSpacing: TICK_SPACING,
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        protocolFeeX64: 0,
        amount0: 1 ether,
        amount1: 3000 * 1e6,
        amount2: 0,
        recipient: address(vaultInstance),
        deadline: block.timestamp + 300,
        swapSourceToken: address(0),
        amountIn0: 0,
        amountOut0Min: 0,
        swapData0: "",
        amountIn1: 0,
        amountOut1Min: 0,
        swapData1: "",
        amountAddMin0: 0,
        amountAddMin1: 0
      }),
      0 ether,
      new address[](0),
      new uint256[](0)
    );

    (address[] memory targets, bytes[] memory dataArray, IPrivateCommon.CallType[] memory callTypes) =
      _createMulticallData(address(nonWhitelistedStrategy), strategyCallData);

    // This should revert due to strategy not being whitelisted
    vm.expectRevert();
    vaultInstance.multicall(targets, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test complete end-to-end workflow
  function test_EndToEnd_CompleteWorkflow() public {
    vm.startPrank(vaultOwner);

    // 1. Create initial LP position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);

    // 2. Add more liquidity
    uint256 additionalWethAmount = 0.5 ether;
    uint256 additionalUsdcAmount = 1500 * 1e6;
    _addLiquidityToPosition(tokenId, additionalWethAmount, additionalUsdcAmount);

    vm.stopPrank();

    // 3. Simulate trading activity to generate fees
    address token0 = WETH < USDC ? WETH : USDC;
    address token1 = WETH < USDC ? USDC : WETH;
    _simulateSwapsToGenerateFees(token0, token1, FEE_TIER);

    vm.startPrank(vaultOwner);

    // 4. Manage position (compound fees)
    _transferAndExecuteNFT(tokenId);

    // 5. Verify final state
    uint256 finalNftCount = IERC721(NFPM).balanceOf(address(vaultInstance));
    assertEq(finalNftCount, 1); // Should have 1 NFT position

    // Verify vault still owns the position
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }
}
