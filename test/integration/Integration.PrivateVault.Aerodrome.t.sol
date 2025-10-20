// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, AERODROME_NFPM as NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import { INonfungiblePositionManager as INFPM } from
  "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

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

// Aerodrome Farming Strategy contracts
import { AerodromeFarmingStrategy } from "../../contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol";
import { ICLGauge } from "../../contracts/common/interfaces/protocols/aerodrome/ICLGauge.sol";
import { ICLFactory } from "../../contracts/common/interfaces/protocols/aerodrome/ICLFactory.sol";
import { ICLPool } from "../../contracts/common/interfaces/protocols/aerodrome/ICLPool.sol";

interface ISwapRouter {
  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    int24 tickSpacing;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  /// @notice Swaps `amountIn` of one token for as much as possible of another token
  /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
  /// @return amountOut The amount of the received token
  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
  /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
  /// @return amountOut The amount of the received token
  function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

  struct ExactOutputSingleParams {
    address tokenIn;
    address tokenOut;
    int24 tickSpacing;
    address recipient;
    uint256 deadline;
    uint256 amountOut;
    uint256 amountInMaximum;
    uint160 sqrtPriceLimitX96;
  }

  /// @notice Swaps as little as possible of one token for `amountOut` of another token
  /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
  /// @return amountIn The amount of the input token
  function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);

  struct ExactOutputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountOut;
    uint256 amountInMaximum;
  }

  /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
  /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
  /// @return amountIn The amount of the input token
  function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

contract PrivateVaultIntegrationTest is TestCommon, IERC721Receiver {
  // Test constants
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af; // V3Utils contract on Base
  address constant SWAP_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5; // Aerodrome SwapRouter on Base
  address constant GAUGE = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8; // Gauge contract for WETH/USDC pool
  address constant GAUGE_FACTORY = 0xD30677bd8dd15132F251Cb54CbDA552d2A05Fb08;
  address constant AERO_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // AERO token on Base
  uint8 constant PROTOCOL = 3; // AERODROME
  int24 constant TICK_SPACING = 100;
  int24 constant TICK_LOWER = -887_000;
  int24 constant TICK_UPPER = 887_000;
  uint256 constant Q64 = 0x10000000000000000;

  // Contract instances
  PrivateConfigManager public configManager;
  PrivateVaultFactory public vaultFactory;
  PrivateVault public vaultImplementation;
  V3UtilsStrategy public v3UtilsStrategy;
  AerodromeFarmingStrategy public farmingStrategy;
  PrivateVault public vaultInstance;

  // Test addresses
  address public vaultOwner = USER;
  address public admin = 0x1234567890123456789012345678901234567891;
  address public feeRecipient = makeAddr("feeRecipient");

  function setUp() public {
    // Create mainnet fork for consistent testing environment
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 36_953_600);
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
      whitelistOwners,
      admin
    );

    // Deploy V3UtilsStrategy
    v3UtilsStrategy = new V3UtilsStrategy(V3_UTILS);

    // Deploy AerodromeFarmingStrategy
    farmingStrategy = new AerodromeFarmingStrategy(GAUGE_FACTORY, address(configManager));

    // Add strategies to whitelist
    address[] memory strategiesToAdd = new address[](2);
    strategiesToAdd[0] = address(v3UtilsStrategy);
    strategiesToAdd[1] = address(farmingStrategy);
    vm.stopPrank();

    vm.prank(admin);
    configManager.setWhitelistTargets(strategiesToAdd, true);

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
  function _createLPPosition(uint256 wethAmount, uint256 usdcAmount, bool useNative) internal returns (uint256 tokenId) {
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
      protocol: PROTOCOL, // UNI_V3
      nfpm: NFPM,
      token0: WETH < USDC ? WETH : USDC,
      token1: WETH < USDC ? USDC : WETH,
      fee: 0,
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

    uint256 nativeValue = 0;
    if (useNative) nativeValue = wethAmount;
    // Execute strategy through vault multicall
    vaultInstance.multicall{ value: nativeValue }(targets, callValues, dataArray, callTypes);

    // Return the token ID of the created position
    return IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vaultInstance), 0);
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
      protocol: PROTOCOL, // UNI_V3
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
  function _simulateSwapsToGenerateFees(address token0, address token1, int24 tickSpacing) internal {
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
        tickSpacing: tickSpacing,
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
        tickSpacing: tickSpacing,
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
      protocol: PROTOCOL,
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

  // Helper function to create LP position and stake in gauge in one multicall (no prank management)
  function _zapIntoGauge(uint256 wethAmount, uint256 usdcAmount) internal returns (uint256 tokenId) {
    // Deposit tokens to vault first
    _depositTokens(wethAmount, usdcAmount);

    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = wethAmount;
    amounts[1] = usdcAmount;

    // Prepare multicall with LP creation + gauge staking
    address[] memory targets = new address[](2);
    uint256[] memory callValues = new uint256[](2);
    bytes[] memory dataArray = new bytes[](2);
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);

    // 1. Create LP position
    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: PROTOCOL,
      nfpm: NFPM,
      token0: WETH < USDC ? WETH : USDC,
      token1: WETH < USDC ? USDC : WETH,
      fee: 0,
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

    targets[0] = address(v3UtilsStrategy);
    callValues[0] = 0;
    dataArray[0] = abi.encodeWithSelector(V3UtilsStrategy.swapAndMint.selector, params, 0 ether, tokens, amounts);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    // 2. Stake in gauge (using tokenId = 0 to auto-select the last created token)
    targets[1] = address(farmingStrategy);
    callValues[1] = 0;
    dataArray[1] = abi.encodeWithSelector(
      AerodromeFarmingStrategy.deposit.selector,
      0 // tokenId = 0 means use the last created token
    );
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    // Get the NFT count before executing to find the new tokenId
    uint256 nftCountBefore = IERC721(NFPM).balanceOf(address(vaultInstance));

    // Execute multicall
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    // Find the new tokenId by checking which one was added
    uint256 newTokenId;
    uint256 nftCountAfter = IERC721(NFPM).balanceOf(address(vaultInstance));

    if (nftCountAfter > nftCountBefore) {
      // NFT was minted but not staked (shouldn't happen in this case)
      newTokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vaultInstance), nftCountAfter - 1);
    } else {
      // NFT was staked, so we need to find it in the gauge
      // Get the gauge from the token parameters we used
      address expectedGauge = getExpectedGauge(WETH, USDC, TICK_SPACING);
      uint256[] memory stakedTokens = ICLGauge(expectedGauge).stakedValues(address(vaultInstance));
      require(stakedTokens.length > 0, "No tokens staked");
      newTokenId = stakedTokens[stakedTokens.length - 1]; // Return the most recently staked token
    }

    return newTokenId;
  }

  // Helper function to stake existing LP position in gauge (no prank management)
  function _stakeInGauge(uint256 tokenId) internal {
    bytes memory strategyCallData = abi.encodeWithSelector(AerodromeFarmingStrategy.deposit.selector, tokenId);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // Helper function to unstake LP position from gauge (no prank management)
  function _unstakeFromGauge(uint256 tokenId) internal {
    _unstakeFromGaugeWithFee(tokenId, 0, 0);
  }

  function _unstakeFromGaugeWithFee(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal {
    bytes memory strategyCallData =
      abi.encodeWithSelector(AerodromeFarmingStrategy.withdraw.selector, tokenId, rewardFeeX64, gasFeeX64);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // Helper function to claim AERO rewards from gauge (no prank management)
  function _claimGaugeRewards(uint256 tokenId) internal {
    _claimGaugeRewardsWithFee(tokenId, 0, 0);
  }

  function _claimGaugeRewardsWithFee(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64) internal {
    bytes memory strategyCallData =
      abi.encodeWithSelector(AerodromeFarmingStrategy.harvest.selector, tokenId, rewardFeeX64, gasFeeX64);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    vaultInstance.multicall(targets, callValues, dataArray, callTypes);
  }

  // Helper function for unstake -> operate -> restake multicall (no prank management)
  function _unstakeOperateRestake(
    uint256 tokenId,
    address[] memory targets,
    bytes[] memory dataArray,
    IPrivateCommon.CallType[] memory callTypes
  ) internal {
    // Build complete multicall: unstake + operations + restake
    uint256 totalOperations = 2 + targets.length; // unstake + operations + restake
    address[] memory allTargets = new address[](totalOperations);
    uint256[] memory allCallValues = new uint256[](totalOperations);
    bytes[] memory allData = new bytes[](totalOperations);
    IPrivateCommon.CallType[] memory allCallTypes = new IPrivateCommon.CallType[](totalOperations);

    // 1. Unstake operation
    allTargets[0] = address(farmingStrategy);
    allCallValues[0] = 0;
    allData[0] = abi.encodeWithSelector(AerodromeFarmingStrategy.withdraw.selector, tokenId, 0, 0);
    allCallTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    // 2. LP operations
    for (uint256 i = 0; i < targets.length; i++) {
      allTargets[1 + i] = targets[i];
      allCallValues[1 + i] = 0;
      allData[1 + i] = dataArray[i];
      allCallTypes[1 + i] = callTypes[i];
    }

    // 3. Restake operation
    allTargets[totalOperations - 1] = address(farmingStrategy);
    allCallValues[totalOperations - 1] = 0;
    allData[totalOperations - 1] = abi.encodeWithSelector(AerodromeFarmingStrategy.deposit.selector, tokenId);
    allCallTypes[totalOperations - 1] = IPrivateCommon.CallType.DELEGATECALL;

    // Execute complete multicall
    vaultInstance.multicall(allTargets, allCallValues, allData, allCallTypes);
  }

  // Helper function to increase liquidity while farming (no prank management)
  function _increaseLiquidityWhileFarming(uint256 tokenId, uint256 wethAmount, uint256 usdcAmount) internal {
    // Deposit additional tokens first
    _depositTokens(wethAmount, usdcAmount);

    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = wethAmount;
    amounts[1] = usdcAmount;

    // Prepare swapAndIncreaseLiquidity parameters
    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: PROTOCOL,
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

    // Prepare operation call data
    bytes memory strategyCallData =
      abi.encodeWithSelector(V3UtilsStrategy.swapAndIncreaseLiquidity.selector, params, 0 ether, tokens, amounts);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // Execute unstake -> increase liquidity -> restake
    _unstakeOperateRestake(tokenId, targets, dataArray, callTypes);
  }

  // Helper function to get expected gauge from tokenId
  function getExpectedGaugeFromTokenId(uint256 tokenId) internal view returns (address) {
    (,, address token0, address token1, int24 tickSpacing,,,,,,,) = INFPM(NFPM).positions(tokenId);

    // Ensure tokens are ordered correctly (token0 < token1)
    if (token0 > token1) (token0, token1) = (token1, token0);

    address factory = INFPM(NFPM).factory();
    address pool = ICLFactory(factory).getPool(token0, token1, tickSpacing);
    return ICLPool(pool).gauge();
  }

  // Helper function to get expected gauge from token parameters
  function getExpectedGauge(address tokenA, address tokenB, int24 tickSpacing) internal view returns (address) {
    // Ensure tokens are ordered correctly (token0 < token1)
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

    address factory = INFPM(NFPM).factory();
    address pool = ICLFactory(factory).getPool(token0, token1, tickSpacing);
    return ICLPool(pool).gauge();
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

    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount, false);

    // Verify NFT was received
    uint256 nftCountAfter = IERC721(NFPM).balanceOf(address(vaultInstance));
    assertEq(nftCountAfter, nftCountBefore + 1);

    // Verify the token ID is valid
    assertGt(tokenId, 0);
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test V3UtilsStrategy swapAndMint functionality
  function test_V3UtilsStrategy_SwapAndMintFromWalletNative() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;

    // Record NFT count before
    uint256 nftCountBefore = IERC721(NFPM).balanceOf(address(vaultInstance));

    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount, true);

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
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount, false);

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
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount, false);

    // Verify NFT is in vault before
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();

    // Simulate swaps to generate fees (needs its own prank management)
    address token0 = WETH < USDC ? WETH : USDC;
    address token1 = WETH < USDC ? USDC : WETH;
    _simulateSwapsToGenerateFees(token0, token1, TICK_SPACING);

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
        protocol: PROTOCOL,
        nfpm: NFPM,
        token0: WETH,
        token1: USDC,
        fee: 0,
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
        protocol: PROTOCOL,
        nfpm: NFPM,
        token0: WETH,
        token1: USDC,
        fee: 0,
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
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount, false);

    // 2. Add more liquidity
    uint256 additionalWethAmount = 0.5 ether;
    uint256 additionalUsdcAmount = 1500 * 1e6;
    _addLiquidityToPosition(tokenId, additionalWethAmount, additionalUsdcAmount);

    vm.stopPrank();

    // 3. Simulate trading activity to generate fees
    address token0 = WETH < USDC ? WETH : USDC;
    address token1 = WETH < USDC ? USDC : WETH;
    _simulateSwapsToGenerateFees(token0, token1, TICK_SPACING);

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

  // Test zapping into gauge (LP creation + staking in one transaction)
  function test_ZapIntoGauge() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;

    // Execute zap into gauge
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Get the actual gauge for this position
    address actualGauge = getExpectedGaugeFromTokenId(tokenId);

    // Check gauge balance before and after (we'll assume it increased by 1)
    uint256 stakedCountAfter = ICLGauge(actualGauge).stakedLength(address(vaultInstance));
    assertGt(stakedCountAfter, 0);

    // Verify the specific token is staked
    assertTrue(ICLGauge(actualGauge).stakedContains(address(vaultInstance), tokenId));

    // Verify vault no longer owns the NFT (it's in the gauge)
    assertEq(IERC721(NFPM).ownerOf(tokenId), actualGauge);

    vm.stopPrank();
  }

  // Test staking existing LP position in gauge
  function test_StakeExistingLP() public {
    vm.startPrank(vaultOwner);

    // First create an LP position
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _createLPPosition(wethAmount, usdcAmount, false);

    // Verify vault owns the NFT initially
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    // Get the expected gauge for this position
    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);

    // Check gauge balance before
    uint256 stakedCountBefore = ICLGauge(expectedGauge).stakedLength(address(vaultInstance));

    // Stake the position in the gauge
    _stakeInGauge(tokenId);

    // Verify token is staked in gauge
    uint256 stakedCountAfter = ICLGauge(expectedGauge).stakedLength(address(vaultInstance));
    assertEq(stakedCountAfter, stakedCountBefore + 1);

    // Verify the specific token is staked
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    vm.stopPrank();
  }

  // Test unstaking LP position from gauge
  function test_UnstakeFromGauge() public {
    vm.startPrank(vaultOwner);

    // First zap into gauge
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Get the expected gauge for this position
    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);

    // Verify token is staked
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    // Unstake from gauge
    _unstakeFromGauge(tokenId);

    // Verify token is no longer staked
    assertFalse(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    // Verify vault owns the NFT again
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test claiming AERO rewards from gauge
  function test_ClaimGaugeRewards() public {
    vm.startPrank(vaultOwner);

    // First zap into gauge
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Simulate time passing to accumulate rewards
    vm.warp(block.timestamp + 1 days);

    // Check AERO balance before claiming
    uint256 aeroBefore = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));

    // Claim rewards
    _claimGaugeRewards(tokenId);

    // Check AERO balance after claiming (should be greater or equal, depending on if rewards exist)
    uint256 aeroAfter = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    assertGt(aeroAfter, aeroBefore);

    vm.stopPrank();
  }

  // Test access control for farming operations
  function test_AccessControl_FarmingOperations() public {
    address unauthorized = 0x9999999999999999999999999999999999999999;

    vm.startPrank(unauthorized);

    bytes memory strategyCallData = abi.encodeWithSelector(AerodromeFarmingStrategy.deposit.selector, 1);

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

  // Test error handling for invalid tokenId
  function test_ErrorHandling_InvalidTokenId() public {
    vm.startPrank(vaultOwner);

    // Using tokenId 1 which likely doesn't exist
    bytes memory strategyCallData = abi.encodeWithSelector(AerodromeFarmingStrategy.deposit.selector, 1);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(farmingStrategy), strategyCallData);

    // This should revert due to invalid tokenId (position doesn't exist)
    vm.expectRevert();
    vaultInstance.multicall(targets, callValues, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test complete end-to-end farming workflow
  function test_EndToEnd_FarmingWorkflow() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;

    // 1. Zap into gauge (create LP + stake)
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Get the expected gauge for this position
    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);

    // Verify token is staked
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    // 2. Simulate farming period
    vm.warp(block.timestamp + 7 days);

    // 3. Claim rewards
    uint256 aeroBefore = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    _claimGaugeRewards(tokenId);
    uint256 aeroAfter = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    assertGe(aeroAfter, aeroBefore);

    // 4. Unstake position
    _unstakeFromGauge(tokenId);

    // Verify final state
    assertFalse(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  function test_HarvestFeeCollection() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    vm.warp(block.timestamp + 7 days);

    uint64 rewardFeeX64 = _bpsToX64(500);
    uint64 gasFeeX64 = _bpsToX64(100);

    uint256 vaultBalanceBefore = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceBefore = IERC20(AERO_TOKEN).balanceOf(feeRecipient);

    _claimGaugeRewardsWithFee(tokenId, rewardFeeX64, gasFeeX64);

    uint256 vaultBalanceAfter = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceAfter = IERC20(AERO_TOKEN).balanceOf(feeRecipient);

    uint256 recipientDelta =
      recipientBalanceAfter > recipientBalanceBefore ? recipientBalanceAfter - recipientBalanceBefore : 0;
    uint256 vaultDelta = vaultBalanceAfter > vaultBalanceBefore ? vaultBalanceAfter - vaultBalanceBefore : 0;
    uint256 totalHarvested = recipientDelta + vaultDelta;

    uint256 expectedRewardFee = (totalHarvested * rewardFeeX64) / Q64;
    uint256 expectedGasFee = (totalHarvested * gasFeeX64) / Q64;
    uint256 expectedRecipientDelta = expectedRewardFee + expectedGasFee;
    assertEq(recipientDelta, expectedRecipientDelta);

    vm.stopPrank();
  }

  function test_WithdrawFeeCollection() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);

    vm.warp(block.timestamp + 7 days);

    uint64 rewardFeeX64 = _bpsToX64(500);
    uint64 gasFeeX64 = _bpsToX64(100);

    uint256 vaultBalanceBefore = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceBefore = IERC20(AERO_TOKEN).balanceOf(feeRecipient);

    _unstakeFromGaugeWithFee(tokenId, rewardFeeX64, gasFeeX64);

    uint256 vaultBalanceAfter = IERC20(AERO_TOKEN).balanceOf(address(vaultInstance));
    uint256 recipientBalanceAfter = IERC20(AERO_TOKEN).balanceOf(feeRecipient);

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

    assertFalse(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    vm.stopPrank();
  }

  // Test increasing liquidity while position is farming
  function test_IncreaseLiquidityWhileFarming() public {
    vm.startPrank(vaultOwner);

    // 1. Zap into gauge (create LP + stake)
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Get the expected gauge for this position
    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);

    // Verify token is staked
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    // Get position info before increase
    (,,,,,,, uint128 liquidityBefore,,,,) = INFPM(NFPM).positions(tokenId);

    // 2. Increase liquidity while farming
    uint256 additionalWethAmount = 0.5 ether;
    uint256 additionalUsdcAmount = 1500 * 1e6;
    _increaseLiquidityWhileFarming(tokenId, additionalWethAmount, additionalUsdcAmount);

    // Verify position is still staked after operation
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));
    assertEq(IERC721(NFPM).ownerOf(tokenId), expectedGauge);

    // Verify liquidity increased
    (,,,,,,, uint128 liquidityAfter,,,,) = INFPM(NFPM).positions(tokenId);
    assertGt(liquidityAfter, liquidityBefore);

    vm.stopPrank();
  }

  // Test that liquidity changes persist after restaking
  function test_LiquidityIncreasePersistsAfterRestake() public {
    vm.startPrank(vaultOwner);

    // 1. Create initial LP position and stake
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Get initial liquidity
    (,,,,,,, uint128 initialLiquidity,,,,) = INFPM(NFPM).positions(tokenId);

    // 2. Increase liquidity while farming
    uint256 additionalWethAmount = 0.5 ether;
    uint256 additionalUsdcAmount = 1500 * 1e6;
    _increaseLiquidityWhileFarming(tokenId, additionalWethAmount, additionalUsdcAmount);

    // Get liquidity after increase
    (,,,,,,, uint128 increasedLiquidity,,,,) = INFPM(NFPM).positions(tokenId);
    assertGt(increasedLiquidity, initialLiquidity);

    // 3. Unstake and restake manually to verify persistence
    _unstakeFromGauge(tokenId);
    assertEq(IERC721(NFPM).ownerOf(tokenId), address(vaultInstance));

    // Get the expected gauge for this position
    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);
    _stakeInGauge(tokenId);
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    // 4. Verify liquidity is still the same after unstake/restake cycle
    (,,,,,,, uint128 finalLiquidity,,,,) = INFPM(NFPM).positions(tokenId);
    assertEq(finalLiquidity, increasedLiquidity);

    vm.stopPrank();
  }

  // Test error handling during farming operations
  function test_ErrorHandling_OperationFailureLeavesUnstaked() public {
    vm.startPrank(vaultOwner);

    // 1. Zap into gauge
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);

    // Get the expected gauge for this position
    address expectedGauge = getExpectedGaugeFromTokenId(tokenId);

    // Verify token is staked
    assertTrue(ICLGauge(expectedGauge).stakedContains(address(vaultInstance), tokenId));

    // 2. Try to increase liquidity with insufficient tokens (should fail)
    // Don't deposit tokens first to cause failure
    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = 100 ether; // Excessive amount not deposited
    amounts[1] = 300_000 * 1e6; // Excessive amount not deposited

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: PROTOCOL,
      nfpm: NFPM,
      tokenId: tokenId,
      amount0: WETH < USDC ? 50 ether : 150_000 * 1e6,
      amount1: WETH < USDC ? 150_000 * 1e6 : 50 ether,
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

    bytes memory strategyCallData =
      abi.encodeWithSelector(V3UtilsStrategy.swapAndIncreaseLiquidity.selector, params, 0 ether, tokens, amounts);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // This operation should fail due to insufficient balance
    vm.expectRevert();
    _unstakeOperateRestake(tokenId, targets, dataArray, callTypes);

    vm.stopPrank();
  }

  // Test access control for farming LP operations
  function test_AccessControl_FarmingLPOperations() public {
    address unauthorized = 0x9999999999999999999999999999999999999999;

    vm.startPrank(vaultOwner);
    // First create and stake a position as vault owner
    uint256 wethAmount = 1 ether;
    uint256 usdcAmount = 3000 * 1e6;
    uint256 tokenId = _zapIntoGauge(wethAmount, usdcAmount);
    vm.stopPrank();

    vm.startPrank(unauthorized);

    // Try to perform increase liquidity while farming as unauthorized user
    address[] memory tokens = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    amounts[0] = 0.1 ether;
    amounts[1] = 300 * 1e6;

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: PROTOCOL,
      nfpm: NFPM,
      tokenId: tokenId,
      amount0: WETH < USDC ? 0.05 ether : 150 * 1e6,
      amount1: WETH < USDC ? 150 * 1e6 : 0.05 ether,
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

    bytes memory strategyCallData =
      abi.encodeWithSelector(V3UtilsStrategy.swapAndIncreaseLiquidity.selector, params, 0 ether, tokens, amounts);

    (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory dataArray,
      IPrivateCommon.CallType[] memory callTypes
    ) = _createMulticallData(address(v3UtilsStrategy), strategyCallData);

    // This should revert due to access control
    vm.expectRevert();
    _unstakeOperateRestake(tokenId, targets, dataArray, callTypes);

    vm.stopPrank();
  }
}
