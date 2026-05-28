// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

interface INFPMPositions {
  function positions(uint256 tokenId)
    external
    view
    returns (
      uint96,
      address,
      address,
      address,
      uint24,
      int24,
      int24,
      uint128 liquidity,
      uint256,
      uint256,
      uint128,
      uint128
    );
}

contract SharedVaultIntegrationTest is TestCommon {
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;
  // Uniswap V3 WETH/USDC 0.05% pool constants on Base
  // Must use Uniswap V3 NFPM (not Pancake) because SharedV3Strategy.getPositionAmounts
  // treats positions()[4] as the pool fee (Uniswap semantics), not tickSpacing (Pancake semantics)
  uint24 constant FEE_TIER = 500;
  int24 constant TICK_SPACING = 10;
  int24 constant TICK_LOWER = -887_200;
  int24 constant TICK_UPPER = 887_200;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedVault public vaultImplementation;
  LpFeeTaker public lpFeeTaker;
  SharedV3Strategy public v3Strategy;
  SharedVault public vault;

  address public vaultOwner = USER;
  address public feeRecipient;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 36_953_600);
    vm.selectFork(fork);

    feeRecipient = makeAddr("feeRecipient");

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);
    vm.deal(vaultOwner, 100 ether);

    vm.startPrank(vaultOwner);

    lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));

    // Deploy config manager with strategy whitelisted
    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(vaultOwner, targets, new address[](0), feeRecipient, 0, nfpms, new address[](0));

    // Deploy vault implementation + factory
    vaultImplementation = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(vaultImplementation), WETH);

    // Create vault: vaultOwner deposits 1 WETH + 3000 USDC as initial liquidity
    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    IERC20(USDC).approve(address(vaultFactory), 3000e6);

    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(1 ether), 3000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-Test", vaultTokens, initialAmounts, 0)));

    vm.stopPrank();
  }

  // =========================================================
  // SWAP_AND_MINT: create a new LP position
  // =========================================================

  function test_swapAndMint_createsLpPosition() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    assertEq(vault.getPositionCount(), 1, "should have 1 tracked LP position");
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);
    assertGt(tokenId, 0, "tokenId must be non-zero");
    console.log("SWAP_AND_MINT: position tokenId =", tokenId);

    vm.stopPrank();
  }

  // =========================================================
  // SWAP_AND_INCREASE: add liquidity to existing position
  // =========================================================

  function test_swapAndIncrease_addsLiquidityToPosition() public {
    vm.startPrank(vaultOwner);

    {
      ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
      mintActions[0] = ISharedVault.Action(
        address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
      );
      vault.execute(mintActions);
    }
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);

    {
      ISharedVault.Action[] memory increaseActions = new ISharedVault.Action[](1);
      increaseActions[0] = ISharedVault.Action(
        address(v3Strategy), _swapAndIncreaseData(tokenId, 0.2 ether, 600e6), ISharedCommon.CallType.DELEGATECALL
      );
      vault.execute(increaseActions);
    }

    // Position count unchanged — SWAP_AND_INCREASE doesn't add a new tracked position
    assertEq(vault.getPositionCount(), 1, "position count unchanged after increase");
    console.log("SWAP_AND_INCREASE: increased liquidity on tokenId =", tokenId);

    vm.stopPrank();
  }

  // =========================================================
  // EXECUTE_INSTRUCTIONS: collect fees without removing liquidity
  // =========================================================

  function test_safeTransferNft_collectFees() public {
    vm.startPrank(vaultOwner);

    {
      ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
      mintActions[0] = ISharedVault.Action(
        address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
      );
      vault.execute(mintActions);
    }
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);

    // Collect fees only (0 liquidity removed)
    IV3Utils.Instructions memory instructions = IV3Utils.Instructions({
      whatToDo: IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP,
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
      compoundFees: false,
      liquidity: 0, // collect fees only, no liquidity removal
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp + 300,
      recipient: address(vault),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS), abi.encode(NFPM, tokenId, instructions)
    );

    {
      ISharedVault.Action[] memory collectActions = new ISharedVault.Action[](1);
      collectActions[0] = ISharedVault.Action(address(v3Strategy), data, ISharedCommon.CallType.DELEGATECALL);
      vault.execute(collectActions);
    }

    // Position still tracked — partial collection keeps position alive
    assertEq(vault.getPositionCount(), 1, "position still tracked after fee collection");

    vm.stopPrank();
  }

  // =========================================================
  // EXECUTE_INSTRUCTIONS: full withdraw removes position from tracking
  // =========================================================

  function test_safeTransferNft_fullWithdraw_removesPosition() public {
    vm.startPrank(vaultOwner);

    {
      ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
      mintActions[0] = ISharedVault.Action(
        address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
      );
      vault.execute(mintActions);
    }
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);

    // Query the actual liquidity so we can request full removal precisely
    (,,,,,,, uint128 posLiquidity,,,,) = INFPMPositions(NFPM).positions(tokenId);

    // Full withdrawal: remove all liquidity back to vault
    IV3Utils.Instructions memory instructions = IV3Utils.Instructions({
      whatToDo: IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP,
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
      compoundFees: false,
      liquidity: posLiquidity, // exact liquidity to remove all
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp + 300,
      recipient: address(vault),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS), abi.encode(NFPM, tokenId, instructions)
    );

    {
      ISharedVault.Action[] memory withdrawActions = new ISharedVault.Action[](1);
      withdrawActions[0] = ISharedVault.Action(address(v3Strategy), data, ISharedCommon.CallType.DELEGATECALL);
      vault.execute(withdrawActions);
    }

    assertEq(vault.getPositionCount(), 0, "position removed after full withdrawal");
    console.log("EXECUTE_INSTRUCTIONS full withdraw: position removed");

    vm.stopPrank();
  }

  // =========================================================
  // EXECUTE_INSTRUCTIONS: oversized liquidity request collapses to a full exit
  //
  // Before the cap was added in SharedV3Strategy, passing a sentinel like type(uint128).max
  // would revert at the NFPM. After the fix it collapses to the position's liquidity and
  // becomes a clean full exit, matching V4's `_decreaseV4Principal` semantics.
  // =========================================================
  function test_executeInstructions_withdrawAndCollectAndSwap_capsOversizedLiquidityToFullExit() public {
    vm.startPrank(vaultOwner);

    {
      ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
      mintActions[0] = ISharedVault.Action(
        address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
      );
      vault.execute(mintActions);
    }
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);

    IV3Utils.Instructions memory instructions = IV3Utils.Instructions({
      whatToDo: IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP,
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
      compoundFees: false,
      liquidity: type(uint128).max, // oversized "full exit" sentinel
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp + 300,
      recipient: address(vault),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS), abi.encode(NFPM, tokenId, instructions)
    );

    ISharedVault.Action[] memory withdrawActions = new ISharedVault.Action[](1);
    withdrawActions[0] = ISharedVault.Action(address(v3Strategy), data, ISharedCommon.CallType.DELEGATECALL);

    vault.execute(withdrawActions);

    assertEq(vault.getPositionCount(), 0, "oversized liquidity collapses to full exit and removes position");

    vm.stopPrank();
  }

  // =========================================================
  // Second depositor proportional shares (vault has active LP)
  // =========================================================

  function test_deposit_proportional_withActiveLp() public {
    // vaultOwner deploys liquidity into LP
    vm.startPrank(vaultOwner);
    {
      ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
      mintActions[0] = ISharedVault.Action(
        address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
      );
      vault.execute(mintActions);
    }
    vm.stopPrank();

    // Second depositor: PLAYER_1 deposits proportionally
    address player = makeAddr("player");
    setErc20Balance(WETH, player, 10 ether);
    setErc20Balance(USDC, player, 30_000e6);

    uint256 totalSupplyBefore = vault.totalSupply();
    uint256[4] memory totalBals = vault.getTotalBalances();

    // Compute proportional USDC needed for 0.5 WETH deposit
    uint256 wethIn = 0.5 ether;
    uint256 usdcIn = totalBals[0] > 0 ? (wethIn * totalBals[1]) / totalBals[0] + 1 : 1500e6;

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethIn);
    IERC20(USDC).approve(address(vault), usdcIn);

    uint256[4] memory depositAmounts = [wethIn, usdcIn, uint256(0), 0];
    uint256 shares = vault.deposit(depositAmounts, 0);
    vm.stopPrank();

    assertGt(shares, 0, "second depositor should receive shares");
    assertGt(vault.totalSupply(), totalSupplyBefore, "total supply must increase");
    console.log("Second depositor: shares received =", shares);
  }

  // =========================================================
  // Native ETH deposit + unwrap withdraw
  // =========================================================

  function test_deposit_nativeEth_and_unwrap_withdraw() public {
    address player = makeAddr("ethPlayer");
    setErc20Balance(USDC, player, 10_000e6);
    vm.deal(player, 5 ether);

    vm.startPrank(player);

    // Deposit 1 ETH (auto-wraps to WETH) + proportional USDC
    uint256[4] memory totalBals = vault.getTotalBalances();
    uint256 ethIn = 1 ether;
    uint256 usdcIn = totalBals[0] > 0 ? (ethIn * totalBals[1]) / totalBals[0] + 1 : 3000e6;

    IERC20(USDC).approve(address(vault), usdcIn);

    uint256[4] memory amounts = [ethIn, usdcIn, uint256(0), 0];
    uint256 shares = vault.deposit{ value: ethIn }(amounts, 0);
    assertGt(shares, 0, "should receive shares for ETH deposit");

    uint256 ethBalBefore = player.balance;

    // Withdraw with unwrap=true: WETH payout becomes native ETH
    uint256[4] memory minOut;
    uint256[4] memory withdrawn = vault.withdraw(shares, minOut, true);
    assertGt(withdrawn[0], 0, "WETH/ETH withdrawn must be > 0");
    assertGt(player.balance, ethBalBefore, "player native ETH balance must increase");
    console.log("Native ETH withdraw: ETH received =", withdrawn[0]);

    vm.stopPrank();
  }

  function test_pause_states_do_not_block_withdraw() public {
    uint256 startingShares = vault.balanceOf(vaultOwner);
    uint256[4] memory minOut;

    vm.startPrank(vaultOwner);
    vault.setPaused(true);
    uint256[4] memory perVaultPausedOut = vault.withdraw(startingShares / 4, minOut, false);
    assertGt(perVaultPausedOut[0] + perVaultPausedOut[1], 0, "per-vault paused withdraw should return assets");

    vault.setPaused(false);
    configManager.setVaultPaused(true);
    uint256[4] memory globallyPausedOut = vault.withdraw(startingShares / 4, minOut, false);
    vm.stopPrank();

    assertGt(globallyPausedOut[0] + globallyPausedOut[1], 0, "globally paused withdraw should return assets");
  }

  // =========================================================
  // createVault with execute(actions): initial deposit + immediate LP
  // =========================================================

  function test_createVault_withStrategies() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmt = 1 ether;
    uint256 usdcAmt = 3000e6;

    // WETH initial deposit is paid in native ETH (auto-wrapped by factory).
    // No WETH ERC20 approval needed; only USDC needs approval.
    IERC20(USDC).approve(address(vaultFactory), usdcAmt);

    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [wethAmt, usdcAmt, uint256(0), 0];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(v3Strategy), _swapAndMintData(wethAmt / 2, usdcAmt / 2), ISharedCommon.CallType.DELEGATECALL
    );

    // msg.value = wethAmt for WETH initial deposit (wrapped by factory)
    SharedVault vault2 = SharedVault(
      payable(vaultFactory.createVault{ value: wethAmt }(
          "Vault2-WithStrategies", vaultTokens, initialAmounts, 0, actions
        ))
    );

    // Vault should have exactly 1 LP position created atomically during vault creation
    assertEq(vault2.getPositionCount(), 1, "vault created with LP position");
    console.log("createVault with strategies: LP position count =", vault2.getPositionCount());

    vm.stopPrank();
  }

  // =========================================================
  // withdraw with active LP: triggers exitProportional via delegatecall
  // =========================================================

  function test_withdraw_full_with_lp_position() public {
    vm.startPrank(vaultOwner);

    // Create LP position
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    assertEq(vault.getPositionCount(), 1, "should have 1 LP position");

    uint256 wethBefore = IERC20(WETH).balanceOf(vaultOwner);
    uint256 usdcBefore = IERC20(USDC).balanceOf(vaultOwner);

    // Withdraw all shares — triggers exitProportional which removes the LP position
    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory minAmounts;
    uint256[4] memory withdrawn = vault.withdraw(shares, minAmounts, false);

    assertEq(vault.getPositionCount(), 0, "LP position removed after full withdrawal");
    assertEq(vault.totalSupply(), 0, "no shares remaining");
    assertGt(withdrawn[0] + IERC20(WETH).balanceOf(vaultOwner) - wethBefore, 0, "WETH returned");
    assertGt(withdrawn[1] + IERC20(USDC).balanceOf(vaultOwner) - usdcBefore, 0, "USDC returned");
    console.log("withdraw with LP: WETH =", withdrawn[0], "USDC =", withdrawn[1]);

    vm.stopPrank();
  }

  // =========================================================
  // previewWithdraw includes LP position value
  // =========================================================

  function test_previewWithdraw_includes_lp_value() public {
    vm.startPrank(vaultOwner);

    // Create LP position — idle balances drop, LP value rises
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory preview = vault.previewWithdraw(shares);

    // With LP position deployed, both token previews should be non-zero (LP value included)
    assertGt(preview[0], 0, "WETH preview should reflect LP value");
    assertGt(preview[1], 0, "USDC preview should reflect LP value");
    console.log("previewWithdraw: WETH =", preview[0], "USDC =", preview[1]);

    vm.stopPrank();
  }

  // =========================================================
  // Helpers
  // =========================================================

  function _swapAndMintData(uint256 amount0, uint256 amount1) internal view returns (bytes memory) {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = WETH;
    approveTokens[1] = USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0,
      nfpm: NFPM,
      token0: WETH, // WETH (0x4200..) < USDC (0x8335..) so WETH is token0
      token1: USDC,
      fee: FEE_TIER,
      tickSpacing: TICK_SPACING,
      tickLower: TICK_LOWER,
      tickUpper: TICK_UPPER,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: amount0,
      amount1: amount1,
      amount2: 0,
      recipient: address(0), // overridden by strategy to address(this) = vault
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

    return bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.SWAP_AND_MINT),
      abi.encode(params, approveTokens, approveAmounts, uint256(0))
    );
  }

  function _swapAndIncreaseData(uint256 tokenId, uint256 amount0, uint256 amount1)
    internal
    view
    returns (bytes memory)
  {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = WETH;
    approveTokens[1] = USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0,
      nfpm: NFPM,
      tokenId: tokenId,
      amount0: amount0,
      amount1: amount1,
      amount2: 0,
      recipient: address(0), // overridden by strategy
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

    return bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.SWAP_AND_INCREASE),
      abi.encode(params, approveTokens, approveAmounts, uint256(0))
    );
  }
}
