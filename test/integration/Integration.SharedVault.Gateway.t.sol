// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedVaultGateway } from "../../contracts/shared-vault/core/SharedVaultGateway.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

// ─── Mock swap router ─────────────────────────────────────────────────────────

/// @dev Simulates an external swap aggregator for Gateway integration tests.
///      The gateway approves this contract for tokenIn before calling it with opaque swapData.
///      Caller pre-funds this contract with `amountOut` of tokenOut.
contract MockGatewaySwapRouter {
  using SafeERC20 for IERC20;

  /// @dev Pulled via swapData encoded as abi.encode(tokenIn, tokenOut, amountIn, amountOut).
  ///      Gateway calls this as `swapRouter.call(swapData)` so the function selector must match.
  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
  }
}

// ─── Test contract ────────────────────────────────────────────────────────────

contract SharedVaultGatewayIntegrationTest is TestCommon {
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedVault public vaultImplementation;
  LpFeeTaker public lpFeeTaker;
  SharedV3Strategy public v3Strategy;
  SharedVault public vault;
  SharedVaultGateway public gateway;
  MockGatewaySwapRouter public swapRouter;

  address public gatewayOwner;
  address public vaultOwner = USER;
  address public feeRecipient;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 45_893_511);
    vm.selectFork(fork);

    gatewayOwner = makeAddr("gatewayOwner");
    feeRecipient = makeAddr("feeRecipient");
    swapRouter = new MockGatewaySwapRouter();

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);
    vm.deal(vaultOwner, 100 ether);

    vm.startPrank(vaultOwner);

    lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM;

    configManager = new SharedConfigManager();
    // No swap routers needed in configManager — the gateway has its own independent swapRouter
    configManager.initialize(vaultOwner, targets, new address[](0), feeRecipient, 0, nfpms, new address[](0));

    vaultImplementation = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(vaultImplementation), WETH);

    // Create vault with initial WETH + USDC liquidity
    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    IERC20(USDC).approve(address(vaultFactory), 3000e6);
    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(1 ether), 3000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-Gateway-Test", vaultTokens, initialAmounts, 0)));

    vm.stopPrank();

    // Deploy gateway (owned by gatewayOwner) with the mock swap router
    gateway = new SharedVaultGateway();
    gateway.initialize(gatewayOwner, address(swapRouter), WETH);
  }

  // =========================================================
  // swapAndDeposit: no swap needed — deposit exact proportional amounts
  // =========================================================

  function test_swapAndDeposit_noSwap_depositsExactAmounts() public {
    address player = makeAddr("player");
    uint256 wethDeposit = 0.5 ether;
    uint256 usdcDeposit = 1500e6; // proportional to vault's 1:3000 ratio

    setErc20Balance(WETH, player, wethDeposit);
    setErc20Balance(USDC, player, usdcDeposit);

    vm.startPrank(player);
    IERC20(WETH).approve(address(gateway), wethDeposit);
    IERC20(USDC).approve(address(gateway), usdcDeposit);

    // No swaps — gateway pulls WETH + USDC directly via inputs[]
    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](2);
    inputs[0] = SharedVaultGateway.InputToken({ token: WETH, amount: wethDeposit });
    inputs[1] = SharedVaultGateway.InputToken({ token: USDC, amount: usdcDeposit });

    address[] memory sweepTokens = new address[](2);
    sweepTokens[0] = WETH;
    sweepTokens[1] = USDC;

    uint256[4] memory minDepositAmounts; // no minimum floor
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: inputs,
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: minDepositAmounts,
      slippageBps: 0,
      sweepTokens: sweepTokens
    });

    uint256 shares = gateway.swapAndDeposit(params);
    vm.stopPrank();

    assertGt(shares, 0, "player should receive vault shares");
    assertGt(vault.balanceOf(player), 0, "shares should land in player's wallet");
    console.log("swapAndDeposit no-swap: shares =", shares);
  }

  // =========================================================
  // swapAndDeposit: single-token deposit with WETH→USDC swap
  // =========================================================

  function test_swapAndDeposit_withSwap_convertsWethToUsdc() public {
    address player = makeAddr("player");
    uint256 wethIn = 1 ether; // 0.5 WETH stays as-is, 0.5 WETH swaps to 1500 USDC
    uint256 wethForSwap = 0.5 ether;
    uint256 usdcOut = 1500e6;

    setErc20Balance(WETH, player, wethIn);
    // Pre-fund the mock router with the USDC output
    setErc20Balance(USDC, address(swapRouter), usdcOut);

    vm.startPrank(player);
    IERC20(WETH).approve(address(gateway), wethIn);

    bytes memory swapCalldata = abi.encodeCall(
      MockGatewaySwapRouter.swap,
      (WETH, USDC, wethForSwap, usdcOut)
    );

    // Pull all 1 WETH upfront, then swap 0.5 WETH → USDC (the other 0.5 deposited directly).
    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](1);
    inputs[0] = SharedVaultGateway.InputToken({ token: WETH, amount: wethIn });

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams({
      tokenIn: WETH,
      amountIn: wethForSwap,
      tokenOut: USDC,
      amountOutMin: 0,
      swapData: swapCalldata
    });

    address[] memory sweepTokens = new address[](2);
    sweepTokens[0] = WETH;
    sweepTokens[1] = USDC;

    uint256[4] memory minDepositAmounts;
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: inputs,
      swaps: swaps,
      minDepositAmounts: minDepositAmounts,
      slippageBps: 0,
      sweepTokens: sweepTokens
    });

    uint256 shares = gateway.swapAndDeposit(params);
    vm.stopPrank();

    assertGt(shares, 0, "player should receive vault shares");
    console.log("swapAndDeposit with swap: shares =", shares);
  }

  // =========================================================
  // swapAndDeposit: slippage floor blocks deposit when output too low
  // =========================================================

  function test_swapAndDeposit_revertsOnInsufficientPostSwapBalance() public {
    address player = makeAddr("player");
    uint256 wethIn = 0.5 ether;
    uint256 usdcOut = 1400e6; // below minDepositAmounts[1] = 1500e6

    setErc20Balance(WETH, player, wethIn + 0.5 ether);
    setErc20Balance(USDC, address(swapRouter), usdcOut);

    vm.startPrank(player);
    IERC20(WETH).approve(address(gateway), wethIn + 0.5 ether);

    bytes memory swapCalldata = abi.encodeCall(
      MockGatewaySwapRouter.swap,
      (WETH, USDC, wethIn, usdcOut)
    );

    // Pull all WETH upfront (0.5 to keep + 0.5 to swap = 1 ether), then swap 0.5 WETH → USDC.
    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](1);
    inputs[0] = SharedVaultGateway.InputToken({ token: WETH, amount: wethIn + 0.5 ether });

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams({
      tokenIn: WETH,
      amountIn: wethIn,
      tokenOut: USDC,
      amountOutMin: 0,
      swapData: swapCalldata
    });

    uint256[4] memory minDepositAmounts;
    minDepositAmounts[1] = 1500e6; // require at least 1500 USDC — but only 1400e6 will arrive

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: inputs,
      swaps: swaps,
      minDepositAmounts: minDepositAmounts,
      slippageBps: 0,
      sweepTokens: new address[](0)
    });

    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientPostSwapBalance.selector, uint256(1)));
    gateway.swapAndDeposit(params);
    vm.stopPrank();
  }

  // =========================================================
  // withdrawAndSwap: no swap — withdraw receives vault tokens
  // =========================================================

  function test_withdrawAndSwap_noSwap_returnsVaultTokens() public {
    // First get some shares
    address player = makeAddr("player");
    uint256 wethDeposit = 0.5 ether;
    uint256 usdcDeposit = 1500e6;
    setErc20Balance(WETH, player, wethDeposit);
    setErc20Balance(USDC, player, usdcDeposit);

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethDeposit);
    IERC20(USDC).approve(address(vault), usdcDeposit);
    uint256[4] memory depositAmounts = [wethDeposit, usdcDeposit, uint256(0), 0];
    uint256 shares = vault.deposit(depositAmounts, 0);

    // Approve gateway for shares
    IERC20(address(vault)).approve(address(gateway), shares);

    uint256 wethBefore = IERC20(WETH).balanceOf(player);
    uint256 usdcBefore = IERC20(USDC).balanceOf(player);

    SharedVaultGateway.SwapParams[] memory swaps; // empty: no post-withdraw swap

    address[] memory sweepTokens = new address[](2);
    sweepTokens[0] = WETH;
    sweepTokens[1] = USDC;

    uint256[4] memory minWithdrawAmounts;
    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: minWithdrawAmounts,
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: sweepTokens
    });

    gateway.withdrawAndSwap(params);
    vm.stopPrank();

    assertGt(IERC20(WETH).balanceOf(player), wethBefore, "player should receive WETH back");
    assertGt(IERC20(USDC).balanceOf(player), usdcBefore, "player should receive USDC back");
    console.log(
      "withdrawAndSwap no-swap: WETH =",
      IERC20(WETH).balanceOf(player) - wethBefore,
      "USDC =",
      IERC20(USDC).balanceOf(player) - usdcBefore
    );
  }

  // =========================================================
  // withdrawAndSwap: post-withdraw swap — USDC → WETH via mock router
  // =========================================================

  function test_withdrawAndSwap_withSwap_convertsUsdcToWeth() public {
    // Get player some shares
    address player = makeAddr("player");
    uint256 wethDeposit = 0.5 ether;
    uint256 usdcDeposit = 1500e6;
    setErc20Balance(WETH, player, wethDeposit);
    setErc20Balance(USDC, player, usdcDeposit);

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethDeposit);
    IERC20(USDC).approve(address(vault), usdcDeposit);
    uint256[4] memory depositAmounts = [wethDeposit, usdcDeposit, uint256(0), 0];
    uint256 shares = vault.deposit(depositAmounts, 0);
    vm.stopPrank();

    // Preview how much USDC the player will receive on withdraw
    uint256[4] memory preview = vault.previewWithdraw(shares);
    uint256 expectedUsdc = preview[1];
    uint256 expectedWethFromSwap = expectedUsdc / 3000; // rough: 1 WETH = 3000 USDC

    // Pre-fund mock router with WETH output for the swap
    setErc20Balance(WETH, address(swapRouter), expectedWethFromSwap);

    vm.startPrank(player);
    IERC20(address(vault)).approve(address(gateway), shares);

    bytes memory swapCalldata = abi.encodeCall(
      MockGatewaySwapRouter.swap,
      (USDC, WETH, expectedUsdc, expectedWethFromSwap)
    );

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams({
      tokenIn: USDC,
      amountIn: 0, // 0 = use full gateway balance of USDC after withdraw
      tokenOut: WETH,
      amountOutMin: 0,
      swapData: swapCalldata
    });

    address[] memory sweepTokens = new address[](2);
    sweepTokens[0] = WETH;
    sweepTokens[1] = USDC;

    uint256[4] memory minWithdrawAmounts;
    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: minWithdrawAmounts,
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: sweepTokens
    });

    uint256 wethBefore = IERC20(WETH).balanceOf(player);
    gateway.withdrawAndSwap(params);
    vm.stopPrank();

    // Player should receive their WETH back + extra WETH from swap
    assertGt(IERC20(WETH).balanceOf(player), wethBefore, "player WETH should increase");
    console.log("withdrawAndSwap with swap: WETH gained =", IERC20(WETH).balanceOf(player) - wethBefore);
  }

  // =========================================================
  // withdrawAndSwap: swap fails → revert propagates
  // =========================================================

  function test_withdrawAndSwap_revertsWhenSwapFails() public {
    address player = makeAddr("player");
    uint256 wethDeposit = 0.5 ether;
    uint256 usdcDeposit = 1500e6;
    setErc20Balance(WETH, player, wethDeposit);
    setErc20Balance(USDC, player, usdcDeposit);

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethDeposit);
    IERC20(USDC).approve(address(vault), usdcDeposit);
    uint256[4] memory depositAmounts = [wethDeposit, usdcDeposit, uint256(0), 0];
    uint256 shares = vault.deposit(depositAmounts, 0);
    IERC20(address(vault)).approve(address(gateway), shares);

    // Bad calldata that will cause the router to revert
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams({
      tokenIn: USDC,
      amountIn: 0,
      tokenOut: WETH,
      amountOutMin: 0,
      swapData: abi.encodeWithSignature("nonexistentFunction()")
    });

    uint256[4] memory minWithdrawAmounts;
    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: minWithdrawAmounts,
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: new address[](0)
    });

    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.SwapFailed.selector, uint256(0)));
    gateway.withdrawAndSwap(params);
    vm.stopPrank();
  }

  // =========================================================
  // Gateway paused: both deposit and withdraw revert
  // =========================================================

  function test_swapAndDeposit_revertsWhenGatewayPaused() public {
    vm.prank(gatewayOwner);
    gateway.setPaused(true);

    address player = makeAddr("player");
    setErc20Balance(WETH, player, 1 ether);

    vm.startPrank(player);
    IERC20(WETH).approve(address(gateway), 1 ether);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: new SharedVaultGateway.InputToken[](0),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), 0, 0, 0],
      slippageBps: 0,
      sweepTokens: new address[](0)
    });

    vm.expectRevert();
    gateway.swapAndDeposit(params);
    vm.stopPrank();
  }

  // =========================================================
  // swapAndDeposit emits event
  // =========================================================

  function test_swapAndDeposit_emitsEvent() public {
    address player = makeAddr("player");
    uint256 wethDeposit = 0.5 ether;
    uint256 usdcDeposit = 1500e6;
    setErc20Balance(WETH, player, wethDeposit);
    setErc20Balance(USDC, player, usdcDeposit);

    vm.startPrank(player);
    IERC20(WETH).approve(address(gateway), wethDeposit);
    IERC20(USDC).approve(address(gateway), usdcDeposit);

    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](2);
    inputs[0] = SharedVaultGateway.InputToken({ token: WETH, amount: wethDeposit });
    inputs[1] = SharedVaultGateway.InputToken({ token: USDC, amount: usdcDeposit });

    uint256[4] memory minDepositAmounts;
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: inputs,
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: minDepositAmounts,
      slippageBps: 0,
      sweepTokens: new address[](0)
    });

    vm.expectEmit(true, true, false, false, address(gateway));
    emit SharedVaultGateway.SwapAndDeposit(address(vault), player, 0 /* shares checked separately */);
    gateway.swapAndDeposit(params);
    vm.stopPrank();
  }
}
