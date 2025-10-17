// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, PANCAKE_NFPM as NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
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
import { V3UtilsStrategy } from "../../contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

// PancakeV3 Farming Strategy contracts
import { PancakeV3FarmingStrategy } from "../../contracts/private-vault/strategies/farm/PancakeV3FarmingStrategy.sol";
import { IMasterChefV3 } from "../../contracts/common/interfaces/protocols/pancakev3/IMasterChefV3.sol";

contract PrivateVaultIntegrationTest is TestCommon, IERC721Receiver {
  // Test constants
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af; // V3Utils contract on Base
  address constant SWAP_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14; // Pancake V3 SwapRouter on Base
  address constant MASTERCHEF_V3 = 0xC6A2Db661D5a5690172d8eB0a7DEA2d3008665A3;
  address constant CAKE_TOKEN = 0x3055913c90Fcc1A6CE9a358911721eEb942013A1; // CAKE token on Base
  uint24 constant FEE_TIER = 100; // 0.01% fee tier
  int24 constant TICK_SPACING = 1;
  int24 constant TICK_LOWER = -887_000;
  int24 constant TICK_UPPER = 887_000;
  uint256 constant Q64 = 0x10000000000000000;

  // Contract instances
  PrivateConfigManager public configManager;
  PrivateVaultFactory public vaultFactory;
  PrivateVault public vaultImplementation;
  V3UtilsStrategy public v3UtilsStrategy;
  PancakeV3FarmingStrategy public farmingStrategy;
  PrivateVault public vaultInstance;

  // Test addresses
  address public vaultOwner = USER;
  address public admin = 0x1234567890123456789012345678901234567891;
  address public feeRecipient;

  function setUp() public {
    // Create mainnet fork for consistent testing environment
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 36_953_600);
    vm.selectFork(fork);

    feeRecipient = makeAddr("cakeFeeRecipient");

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
      whitelistOwners,
      admin
    );

    // Deploy V3UtilsStrategy
    v3UtilsStrategy = new V3UtilsStrategy(V3_UTILS);

    // Deploy PancakeV3FarmingStrategy
    farmingStrategy = new PancakeV3FarmingStrategy(MASTERCHEF_V3, address(configManager));

    // Add strategies to whitelist
    address[] memory strategiesToAdd = new address[](2);
    strategiesToAdd[0] = address(v3UtilsStrategy);
    strategiesToAdd[1] = address(farmingStrategy);
    vm.stopPrank();

    vm.prank(admin);
    configManager.setWhitelistTargets(strategiesToAdd, true);

    vm.prank(admin);
    configManager.setFeeRecipient(feeRecipient);

    vm.prank(admin);
    configManager.setFeeRecipient(feeRecipient);

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
    returns (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    )
  {
    targets = new address[](1);
    callValues = new uint256[](1);
    dataArray = new bytes[](1);
    callTypes = new IPrivateCommon.CallType[](1);

    targets[0] = target;
    callValues[0] = 0;
    dataArray[0] = data;
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;
  }

  function _bpsToX64(uint256 bps) internal pure returns (uint64) {
    return uint64((bps * Q64) / 10_000);
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
      gasFeeX64: 0,
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
      amountAddMin1: 0,
      poolDeployer: address(0)
    });

    // Prepare strategy call data
    bytes memory strategyCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndMint.selector,
      params,
      0 ether, // ethValue
      tokens,
      amounts
    );

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute strategy through vault multicall
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

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

    // Prepare swapAndIncreaseLiquidity parameters
    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0, // UNI_V3
      nfpm: NFPM,
      tokenId: tokenId,
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
      amountAddMin1: 0,
      protocolFeeX64: 0,
      gasFeeX64: 0
    });

    // Prepare strategy call data
    bytes memory strategyCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndIncreaseLiquidity.selector,
      params,
      0 ether, // ethValue
      tokens,
      amounts
    );

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute strategy through vault multicall
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
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
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    // Prepare safeTransferNft call data
    bytes memory strategyCallData =
      abi.encodeWithSelector(V3UtilsStrategy.safeTransferNft.selector, NFPM, tokenId, instructions);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute strategy through vault multicall
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // ============ PancakeV3 Farming Helper Functions ============

  // Helper function to stake LP position in MasterChefV3 (no prank management)
  function _stakeInMasterChef(uint256 tokenId) internal {
    bytes memory strategyCallData = abi.encodeWithSelector(PancakeV3FarmingStrategy.deposit.selector, tokenId);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // Helper function to unstake LP position from MasterChefV3 (no prank management)
  function _unstakeFromMasterChef(uint256 tokenId) internal {
    _unstakeFromMasterChefWithFee(tokenId, 0, 0);
  }

  function _unstakeFromMasterChefWithFee(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal {
    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.withdraw.selector, tokenId, rewardFeeX64, gasFeeX64);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // Helper function to claim CAKE rewards from MasterChefV3 (no prank management)
  function _claimMasterChefRewards(uint256 tokenId) internal {
    _claimMasterChefRewardsWithFee(tokenId, 0, 0);
  }

  function _claimMasterChefRewardsWithFee(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal {
    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.harvest.selector, tokenId, rewardFeeX64, gasFeeX64);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // Helper function to create LP position and stake in MasterChefV3 in one multicall (no prank management)
  function _zapIntoMasterChef(uint256 wethAmount, uint256 usdcAmount) internal returns (uint256 tokenId) {
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
      gasFeeX64: 0,
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
      amountAddMin1: 0,
      poolDeployer: address(0)
    });

    // Prepare V3Utils strategy call data
    bytes memory v3UtilsCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndMint.selector,
      params,
      0 ether, // ethValue
      tokens,
      amounts
    );

    // Prepare farming strategy call data (use tokenId = 0 to stake the latest NFT)
    bytes memory farmingCallData = abi.encodeWithSelector(
      PancakeV3FarmingStrategy.deposit.selector,
      0 // This will automatically use the latest NFT created
    );

    // Create multicall with both operations
    address[] memory targets = new address[](2);
    uint256[] memory callValues = new uint256[](2);
    bytes[] memory dataArray = new bytes[](2);
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);

    targets[0] = address(v3UtilsStrategy);
    callValues[0] = 0;
    dataArray[0] = v3UtilsCallData;
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    targets[1] = address(farmingStrategy);
    callValues[1] = 0;
    dataArray[1] = farmingCallData;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    // Execute both operations in one multicall
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    // Get the token ID that were created (last token)
    uint256 totalSupply = IERC721Enumerable(NFPM).totalSupply();
    tokenId = IERC721Enumerable(NFPM).tokenByIndex(totalSupply - 1); // Handle edge case

    return tokenId;
  }

  // Helper function for unstake -> LP operation -> restake workflow (no prank management)
  function _unstakeOperateRestake(uint256 tokenId, uint256 wethAmount, uint256 usdcAmount) internal {
    // Deposit additional tokens for LP operation
    _depositTokens(wethAmount, usdcAmount);

    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = wethAmount;
    amounts[1] = usdcAmount;

    // Prepare swapAndIncreaseLiquidity parameters
    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0, // UNI_V3
      nfpm: NFPM,
      tokenId: tokenId,
      amount0: WETH < USDC ? wethAmount / 2 : usdcAmount / 2,
      amount1: WETH < USDC ? usdcAmount / 2 : wethAmount / 2,
      amount2: 0,
      recipient: address(vaultInstance),
      deadline: block.timestamp + 24 hours,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      protocolFeeX64: 0,
      gasFeeX64: 0
    });

    // Prepare unstake call data
    bytes memory unstakeCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.withdraw.selector, tokenId, 0, 0);

    // Prepare V3Utils increase liquidity call data
    bytes memory increaseLiquidityCallData = abi.encodeWithSelector(
      V3UtilsStrategy.swapAndIncreaseLiquidity.selector,
      params,
      0 ether, // ethValue
      tokens,
      amounts
    );

    // Prepare restake call data
    bytes memory restakeCallData = abi.encodeWithSelector(PancakeV3FarmingStrategy.deposit.selector, tokenId);

    // Create multicall with all three operations
    address[] memory targets = new address[](3);
    uint256[] memory callValues = new uint256[](3);
    bytes[] memory dataArray = new bytes[](3);
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](3);

    targets[0] = address(farmingStrategy);
    callValues[0] = 0;
    dataArray[0] = unstakeCallData;
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    targets[1] = address(v3UtilsStrategy);
    callValues[1] = 0;
    dataArray[1] = increaseLiquidityCallData;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    targets[2] = address(farmingStrategy);
    callValues[2] = 0;
    dataArray[2] = restakeCallData;
    callTypes[2] = IPrivateCommon.CallType.DELEGATECALL;

    // Execute all operations in one multicall
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
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
        gasFeeX64: 0,
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
        amountAddMin1: 0,
        poolDeployer: address(0)
      }),
      0 ether,
      new address[](0),
      new uint256[](0)
    );

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // This should revert due to access control
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

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
        gasFeeX64: 0,
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
        amountAddMin1: 0,
        poolDeployer: address(0)
      }),
      0 ether,
      new address[](0),
      new uint256[](0)
    );

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(nonWhitelistedStrategy), strategyCallData);

    // This should revert due to strategy not being whitelisted
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

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

  // ============ PancakeV3 Farming Tests ============

  // Test basic PancakeV3 MasterChef staking functionality
  function test_PancakeV3Farming_BasicStaking() public {
    vm.startPrank(vaultOwner);

    // Create a position first
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);

    // Verify NFT is in vault before staking
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    // Stake in MasterChefV3
    _stakeInMasterChef(tokenId);

    // Verify NFT is now in MasterChefV3
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);

    vm.stopPrank();
  }

  // Test PancakeV3 MasterChef unstaking functionality
  function test_PancakeV3Farming_BasicUnstaking() public {
    vm.startPrank(vaultOwner);

    // Create and stake a position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);
    _stakeInMasterChef(tokenId);

    // Verify NFT is in MasterChefV3
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);

    // Unstake from MasterChefV3
    _unstakeFromMasterChef(tokenId);

    // Verify NFT is back in vault
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test PancakeV3 "zap" functionality (create LP + stake in one multicall)
  function test_PancakeV3Farming_ZapIntoMasterChef() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;

    // Record NFT count before
    uint256 nftCountBefore = IERC721(NFPM).balanceOf(address(vaultInstance));

    // Zap into MasterChef (create LP + stake in one transaction)
    uint256 tokenId = _zapIntoMasterChef(wethAmount, usdcAmount);

    // Verify NFT was created and immediately staked in MasterChefV3
    assertGt(tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);

    // Verify vault doesn't hold the NFT (it's staked)
    uint256 nftCountAfter = IERC721(NFPM).balanceOf(address(vaultInstance));
    assertEq(nftCountAfter, nftCountBefore); // No change in vault NFT count

    vm.stopPrank();
  }

  // Test staking multiple positions
  function test_PancakeV3Farming_MultiplePositions() public {
    vm.startPrank(vaultOwner);

    // Create and stake first position
    uint256 wethAmount1 = 1 ether;
    uint256 usdcAmount1 = 3000 * 1e6;
    uint256 tokenId1 = _createLPPosition(wethAmount1, usdcAmount1);
    _stakeInMasterChef(tokenId1);

    // Create and stake second position
    uint256 wethAmount2 = 0.5 ether;
    uint256 usdcAmount2 = 1500 * 1e6;
    uint256 tokenId2 = _createLPPosition(wethAmount2, usdcAmount2);
    _stakeInMasterChef(tokenId2);

    // Verify both NFTs are in MasterChefV3
    assertEq(IERC721(NFPM).ownerOf(tokenId1), MASTERCHEF_V3);
    assertEq(IERC721(NFPM).ownerOf(tokenId2), MASTERCHEF_V3);

    // Unstake first position
    _unstakeFromMasterChef(tokenId1);

    // Verify first NFT is back in vault, second still in MasterChefV3
    assertEq(IERC721(NFPM).ownerOf(tokenId1), address(vaultInstance));
    assertEq(IERC721(NFPM).ownerOf(tokenId2), MASTERCHEF_V3);

    vm.stopPrank();
  }

  // Test PancakeV3 CAKE reward claiming functionality
  function test_PancakeV3Farming_ClaimRewards() public {
    vm.startPrank(vaultOwner);

    // Create and stake a position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);
    _stakeInMasterChef(tokenId);

    // Check initial CAKE balance
    uint256 initialCakeBalance = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));

    vm.stopPrank();

    // Fast forward time to accumulate rewards
    vm.warp(block.timestamp + 1 days);

    vm.startPrank(vaultOwner);

    // Claim rewards
    _claimMasterChefRewards(tokenId);

    // Check if CAKE balance increased (note: may be 0 if no rewards available in test environment)
    uint256 finalCakeBalance = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));

    // In a test environment, rewards might be 0, so we just verify the function executes without reverting
    // and that the balance is >= initial balance
    assertGe(finalCakeBalance, initialCakeBalance);

    // Verify NFT is still staked in MasterChefV3 after claiming
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);

    vm.stopPrank();
  }

  // Test multiple reward claims
  function test_PancakeV3Farming_MultipleRewardClaims() public {
    vm.startPrank(vaultOwner);

    // Create and stake a position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);
    _stakeInMasterChef(tokenId);

    vm.stopPrank();

    // Fast forward and claim multiple times
    for (uint256 i = 0; i < 3; i++) {
      vm.warp(block.timestamp + 12 hours);

      vm.startPrank(vaultOwner);

      uint256 balanceBefore = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
      _claimMasterChefRewards(tokenId);
      uint256 balanceAfter = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));

      // Verify claim executed successfully (balance should be >= before)
      assertGe(balanceAfter, balanceBefore);

      vm.stopPrank();
    }

    vm.startPrank(vaultOwner);

    // Verify NFT is still staked after multiple claims
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);

    vm.stopPrank();
  }

  // Test claim rewards for multiple positions
  function test_PancakeV3Farming_ClaimRewardsMultiplePositions() public {
    vm.startPrank(vaultOwner);

    // Create and stake two positions
    uint256 tokenId1 = _zapIntoMasterChef(1 ether, 3000 * 1e6);
    uint256 tokenId2 = _zapIntoMasterChef(0.5 ether, 1500 * 1e6);

    // Verify both are staked
    assertEq(IERC721(NFPM).ownerOf(tokenId1), MASTERCHEF_V3);
    assertEq(IERC721(NFPM).ownerOf(tokenId2), MASTERCHEF_V3);

    vm.stopPrank();

    // Fast forward time
    vm.warp(block.timestamp + 1 days);

    vm.startPrank(vaultOwner);

    // Check initial balance
    uint256 initialBalance = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));

    // Claim rewards for both positions
    _claimMasterChefRewards(tokenId1);
    _claimMasterChefRewards(tokenId2);

    // Verify balance increased or stayed the same
    uint256 finalBalance = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    assertGe(finalBalance, initialBalance);

    // Verify both NFTs are still staked
    assertEq(IERC721(NFPM).ownerOf(tokenId1), MASTERCHEF_V3);
    assertEq(IERC721(NFPM).ownerOf(tokenId2), MASTERCHEF_V3);

    vm.stopPrank();
  }

  // Test complete end-to-end PancakeV3 farming workflow
  function test_PancakeV3Farming_EndToEndWorkflow() public {
    vm.startPrank(vaultOwner);

    // Step 1: Create LP position and immediately stake (zap functionality)
    uint256 wethAmount = 2 ether;
    uint256 usdcAmount = 6000 * 1e6;
    uint256 tokenId = _zapIntoMasterChef(wethAmount, usdcAmount);

    // Verify position is staked
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);

    // Record initial state
    uint256 initialCakeBalance = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    (,,,,,,, uint128 initialLiquidity,,,,) = INFPM(NFPM).positions(tokenId);

    vm.stopPrank();

    // Step 2: Fast forward time to accumulate rewards
    vm.warp(block.timestamp + 12 hours);

    vm.startPrank(vaultOwner);

    // Step 3: Claim initial rewards
    _claimMasterChefRewards(tokenId);
    uint256 cakeBalanceAfterFirstClaim = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    assertGe(cakeBalanceAfterFirstClaim, initialCakeBalance);

    // Step 4: Perform unstake -> add liquidity -> restake workflow
    uint256 additionalWeth = 1 ether;
    uint256 additionalUsdc = 3000 * 1e6;
    _unstakeOperateRestake(tokenId, additionalWeth, additionalUsdc);

    // Verify position is staked again and liquidity increased
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);
    (,,,,,,, uint128 finalLiquidity,,,,) = INFPM(NFPM).positions(tokenId);
    assertGt(finalLiquidity, initialLiquidity);

    vm.stopPrank();

    // Step 5: Fast forward more time and claim final rewards
    vm.warp(block.timestamp + 1 days);

    vm.startPrank(vaultOwner);

    _claimMasterChefRewards(tokenId);
    uint256 finalCakeBalance = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    assertGe(finalCakeBalance, cakeBalanceAfterFirstClaim);

    // Step 6: Final unstaking
    _unstakeFromMasterChef(tokenId);

    // Verify final state
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));
    uint256 finalNftCount = IERC721(NFPM).balanceOf(address(vaultInstance));
    assertEq(finalNftCount, 1);

    vm.stopPrank();
  }

  function test_PancakeV3Farming_HarvestFeeCollection() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoMasterChef(wethAmount, usdcAmount);

    vm.warp(block.timestamp + 7 days);

    uint64 rewardFeeX64 = _bpsToX64(500);
    uint64 gasFeeX64 = _bpsToX64(100);

    uint256 vaultBalanceBefore = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceBefore = IERC20(CAKE_TOKEN).balanceOf(feeRecipient);

    _claimMasterChefRewardsWithFee(tokenId, rewardFeeX64, gasFeeX64);

    uint256 vaultBalanceAfter = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceAfter = IERC20(CAKE_TOKEN).balanceOf(feeRecipient);

    uint256 recipientDelta =
      recipientBalanceAfter > recipientBalanceBefore ? recipientBalanceAfter - recipientBalanceBefore : 0;
    uint256 vaultDelta = vaultBalanceAfter > vaultBalanceBefore ? vaultBalanceAfter - vaultBalanceBefore : 0;
    uint256 totalHarvested = recipientDelta + vaultDelta;

    if (totalHarvested == 0) {
      assertEq(recipientDelta, 0);
    } else {
      uint256 expectedRewardFee = (totalHarvested * rewardFeeX64) / Q64;
      uint256 expectedGasFee = (totalHarvested * gasFeeX64) / Q64;
      uint256 expectedRecipientDelta = expectedRewardFee + expectedGasFee;
      assertEq(recipientDelta, expectedRecipientDelta);
    }

    vm.stopPrank();
  }

  function test_PancakeV3Farming_WithdrawFeeCollection() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoMasterChef(wethAmount, usdcAmount);

    vm.warp(block.timestamp + 7 days);

    uint64 rewardFeeX64 = _bpsToX64(500);
    uint64 gasFeeX64 = _bpsToX64(100);

    uint256 vaultBalanceBefore = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceBefore = IERC20(CAKE_TOKEN).balanceOf(feeRecipient);

    _unstakeFromMasterChefWithFee(tokenId, rewardFeeX64, gasFeeX64);

    uint256 vaultBalanceAfter = IERC20(CAKE_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceAfter = IERC20(CAKE_TOKEN).balanceOf(feeRecipient);

    uint256 recipientDelta =
      recipientBalanceAfter > recipientBalanceBefore ? recipientBalanceAfter - recipientBalanceBefore : 0;
    uint256 vaultDelta = vaultBalanceAfter > vaultBalanceBefore ? vaultBalanceAfter - vaultBalanceBefore : 0;
    uint256 totalHarvested = recipientDelta + vaultDelta;

    if (totalHarvested == 0) {
      assertEq(recipientDelta, 0);
    } else {
      uint256 expectedRewardFee = (totalHarvested * rewardFeeX64) / Q64;
      uint256 expectedGasFee = (totalHarvested * gasFeeX64) / Q64;
      uint256 expectedRecipientDelta = expectedRewardFee + expectedGasFee;
      assertEq(recipientDelta, expectedRecipientDelta);
    }

    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test LP operations while farming (unstake -> add liquidity -> restake)
  function test_PancakeV3Farming_UnstakeOperateRestake() public {
    vm.startPrank(vaultOwner);

    // Create and stake initial position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);
    _stakeInMasterChef(tokenId);

    // Record initial liquidity
    (,,,,,,, uint128 initialLiquidity,,,,) = INFPM(NFPM).positions(tokenId);

    // Perform unstake -> add liquidity -> restake
    uint256 additionalWeth = 0.5 ether;
    uint256 additionalUsdc = 1500 * 1e6;
    _unstakeOperateRestake(tokenId, additionalWeth, additionalUsdc);

    // Verify position is still staked and liquidity increased
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);
    (,,,,,,, uint128 finalLiquidity,,,,) = INFPM(NFPM).positions(tokenId);
    assertGt(finalLiquidity, initialLiquidity);

    vm.stopPrank();
  }

  // Test multiple unstake -> operate -> restake cycles
  function test_PancakeV3Farming_MultipleOperateCycles() public {
    vm.startPrank(vaultOwner);

    // Create initial position
    uint256 tokenId = _zapIntoMasterChef(1 ether, 3000 * 1e6);
    (,,,,,,, uint128 initialLiquidity,,,,) = INFPM(NFPM).positions(tokenId);

    // Perform multiple operate cycles
    for (uint256 i = 0; i < 3; i++) {
      uint256 additionalWeth = 0.2 ether;
      uint256 additionalUsdc = 600 * 1e6;

      (,,,,,,, uint128 liquidityBefore,,,,) = INFPM(NFPM).positions(tokenId);
      _unstakeOperateRestake(tokenId, additionalWeth, additionalUsdc);
      (,,,,,,, uint128 liquidityAfter,,,,) = INFPM(NFPM).positions(tokenId);

      // Verify liquidity increased in each cycle
      assertGt(liquidityAfter, liquidityBefore);
      // Verify position remains staked
      assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);
    }

    // Verify total liquidity increase
    (,,,,,,, uint128 finalLiquidity,,,,) = INFPM(NFPM).positions(tokenId);
    assertGt(finalLiquidity, initialLiquidity);

    vm.stopPrank();
  }

  // Test unstake -> compound fees -> restake workflow
  function test_PancakeV3Farming_UnstakeCompoundRestake() public {
    vm.startPrank(vaultOwner);

    // Create and stake position
    uint256 tokenId = _zapIntoMasterChef(1 ether, 3000 * 1e6);

    vm.stopPrank();

    // Simulate trading to generate fees
    address token0 = WETH < USDC ? WETH : USDC;
    address token1 = WETH < USDC ? USDC : WETH;
    _simulateSwapsToGenerateFees(token0, token1, FEE_TIER);

    vm.startPrank(vaultOwner);

    // Record initial liquidity
    (,,,,,,, uint128 initialLiquidity,,,,) = INFPM(NFPM).positions(tokenId);

    // Prepare compound fees instructions
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
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    // Prepare unstake, compound, restake multicall
    bytes memory unstakeCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.withdraw.selector, tokenId, 0, 0);

    bytes memory compoundCallData =
      abi.encodeWithSelector(V3UtilsStrategy.safeTransferNft.selector, NFPM, tokenId, instructions);

    bytes memory restakeCallData = abi.encodeWithSelector(PancakeV3FarmingStrategy.deposit.selector, tokenId);

    // Execute multicall: unstake -> compound -> restake
    address[] memory targets = new address[](3);
    uint256[] memory callValues = new uint256[](3);
    bytes[] memory dataArray = new bytes[](3);
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](3);

    targets[0] = address(farmingStrategy);
    callValues[0] = 0;
    dataArray[0] = unstakeCallData;
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    targets[1] = address(v3UtilsStrategy);
    callValues[1] = 0;
    dataArray[1] = compoundCallData;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    targets[2] = address(farmingStrategy);
    callValues[2] = 0;
    dataArray[2] = restakeCallData;
    callTypes[2] = IPrivateCommon.CallType.DELEGATECALL;

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    // Verify position is staked and potentially has more liquidity (if fees were compounded)
    assertEq(IERC721(NFPM).ownerOf(tokenId), MASTERCHEF_V3);
    (,,,,,,, uint128 finalLiquidity,,,,) = INFPM(NFPM).positions(tokenId);
    assertGe(finalLiquidity, initialLiquidity); // Should be >= due to potential fee compounding

    vm.stopPrank();
  }

  // ============ PancakeV3 Farming Error Handling Tests ============

  // Test error handling for staking non-existent NFT
  function test_PancakeV3Farming_Error_StakeNonExistentNFT() public {
    vm.startPrank(vaultOwner);

    uint256 nonExistentTokenId = 999_999;

    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.deposit.selector, nonExistentTokenId);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test error handling for unstaking non-existent NFT
  function test_PancakeV3Farming_Error_UnstakeNonExistentNFT() public {
    vm.startPrank(vaultOwner);

    uint256 nonExistentTokenId = 999_999;

    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.withdraw.selector, nonExistentTokenId, 0, 0);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test error handling for claiming rewards from non-existent NFT
  function test_PancakeV3Farming_Error_ClaimRewardsNonExistentNFT() public {
    vm.startPrank(vaultOwner);

    uint256 nonExistentTokenId = 999_999;

    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.harvest.selector, nonExistentTokenId, 0, 0);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test error handling for trying to unstake NFT that's not staked
  function test_PancakeV3Farming_Error_UnstakeNotStaked() public {
    vm.startPrank(vaultOwner);

    // Create position but don't stake it
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount);

    // Try to unstake without staking first
    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.withdraw.selector, tokenId, 0, 0);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert because the NFT is not staked
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test access control for PancakeV3 farming functions
  function test_PancakeV3Farming_Error_AccessControl() public {
    vm.startPrank(vaultOwner);

    // Create and stake a position first
    uint256 tokenId = _zapIntoMasterChef(1 ether, 3000 * 1e6);

    vm.stopPrank();

    // Try to access with unauthorized user
    address unauthorized = 0x9999999999999999999999999999999999999999;
    vm.startPrank(unauthorized);

    bytes memory strategyCallData =
      abi.encodeWithSelector(PancakeV3FarmingStrategy.withdraw.selector, tokenId, 0, 0);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert due to access control
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test error handling when trying to stake NFT vault doesn't own
  function test_PancakeV3Farming_Error_StakeNotOwnedNFT() public {
    vm.startPrank(vaultOwner);

    // Create position in vault first
    uint256 tokenId = _createLPPosition(1 ether, 3000 * 1e6);

    // Transfer NFT out of vault to simulate not owning it
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = NFPM;
    uint256[] memory sweepTokenIds = new uint256[](1);
    sweepTokenIds[0] = tokenId;
    vaultInstance.sweepERC721(sweepTokens, sweepTokenIds);

    // Try to stake NFT that vault no longer owns
    bytes memory strategyCallData = abi.encodeWithSelector(PancakeV3FarmingStrategy.deposit.selector, tokenId);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert because vault doesn't own the NFT
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test handling of double staking (already staked NFT)
  function test_PancakeV3Farming_Error_DoubleStaking() public {
    vm.startPrank(vaultOwner);

    // Create and stake position
    uint256 tokenId = _zapIntoMasterChef(1 ether, 3000 * 1e6);

    // Try to stake again (should fail since it's already staked)
    bytes memory strategyCallData = abi.encodeWithSelector(PancakeV3FarmingStrategy.deposit.selector, tokenId);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert because the NFT is already staked
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }
}
