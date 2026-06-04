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
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

// ─── Mock swap router
// ─────────────────────────────────────────────────────────

/// @dev Minimal mock that simulates a swap aggregator for fork-based CALL tests.
///      The vault pre-approves this contract for `amountIn` before calling it.
///      Caller pre-funds this contract with `amountOut` of `tokenOut`.
contract MockVaultSwapRouter {
  using SafeERC20 for IERC20;

  /// @dev Called by vault via `swapCalldata`. Pulls tokenIn from vault (already approved)
  ///      and pushes tokenOut to vault.
  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
  }
}

// ─── Test contract
// ────────────────────────────────────────────────────────────

contract SharedVaultSwapIntegrationTest is TestCommon {
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedVault public vaultImplementation;
  LpFeeTaker public lpFeeTaker;
  SharedV3Strategy public v3Strategy;
  SharedVault public vault;
  MockVaultSwapRouter public swapRouter;

  address public vaultOwner = USER;
  address public feeRecipient;
  uint256 internal constant SWAP_DATA_SIGNER_PK = 0x5A17;
  address internal swapDataSigner;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 36_953_600);
    vm.selectFork(fork);

    feeRecipient = makeAddr("feeRecipient");
    swapRouter = new MockVaultSwapRouter();
    swapDataSigner = vm.addr(SWAP_DATA_SIGNER_PK);

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);
    vm.deal(vaultOwner, 100 ether);

    vm.startPrank(vaultOwner);

    lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(V3_UTILS);

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM;
    address[] memory routers = new address[](1);
    routers[0] = address(swapRouter);

    configManager = new SharedConfigManager();
    address[] memory signers = new address[](1);
    signers[0] = swapDataSigner;
    configManager.initialize(vaultOwner, targets, new address[](0), feeRecipient, 0, nfpms, routers, signers);

    vaultImplementation = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(vaultImplementation), WETH);

    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    IERC20(USDC).approve(address(vaultFactory), 3000e6);
    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(1 ether), 3000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-Swap-Test", vaultTokens, initialAmounts, 0)));

    vm.stopPrank();
  }

  function _signedSwapData(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData
  ) internal returns (bytes memory) {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 digest = SharedSwapDataSignature.hash(
      address(vault),
      swapDataSigner,
      address(swapRouter),
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(SWAP_DATA_SIGNER_PK, digest);
    return abi.encode(rawSwapData, address(vault), deadline, swapDataSigner, abi.encodePacked(r, s, v));
  }

  // =========================================================
  // WETH → USDC: basic CALL swap via mock router
  // =========================================================

  function test_execute_call_swapsWethToUsdc() public {
    uint256 amountIn = 0.1 ether;
    uint256 amountOut = 300e6; // mock exchange rate: 1 WETH = 3000 USDC

    // Pre-fund the mock router with the expected output
    setErc20Balance(USDC, address(swapRouter), amountOut);

    uint256 wethBefore = IERC20(WETH).balanceOf(address(vault));
    uint256 usdcBefore = IERC20(USDC).balanceOf(address(vault));

    bytes memory swapCalldata = abi.encodeCall(MockVaultSwapRouter.swap, (WETH, USDC, amountIn, amountOut));
    swapCalldata = _signedSwapData(WETH, USDC, amountIn, 0, swapCalldata);
    bytes memory actionData = abi.encode(WETH, USDC, amountIn, uint256(0), swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vault.execute(actions);

    assertEq(IERC20(WETH).balanceOf(address(vault)), wethBefore - amountIn, "vault WETH should decrease by amountIn");
    assertEq(IERC20(USDC).balanceOf(address(vault)), usdcBefore + amountOut, "vault USDC should increase by amountOut");
    console.log("CALL swap WETH->USDC: out =", amountOut);
  }

  // =========================================================
  // USDC → WETH: reverse direction
  // =========================================================

  function test_execute_call_swapsUsdcToWeth() public {
    uint256 amountIn = 3000e6;
    uint256 amountOut = 1 ether;

    setErc20Balance(WETH, address(swapRouter), amountOut);

    uint256 usdcBefore = IERC20(USDC).balanceOf(address(vault));
    uint256 wethBefore = IERC20(WETH).balanceOf(address(vault));

    bytes memory swapCalldata = abi.encodeCall(MockVaultSwapRouter.swap, (USDC, WETH, amountIn, amountOut));
    swapCalldata = _signedSwapData(USDC, WETH, amountIn, 0, swapCalldata);
    bytes memory actionData = abi.encode(USDC, WETH, amountIn, uint256(0), swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vault.execute(actions);

    assertEq(IERC20(USDC).balanceOf(address(vault)), usdcBefore - amountIn, "vault USDC should decrease by amountIn");
    assertEq(IERC20(WETH).balanceOf(address(vault)), wethBefore + amountOut, "vault WETH should increase by amountOut");
    console.log("CALL swap USDC->WETH: out =", amountOut);
  }

  // =========================================================
  // minAmountOut enforced: reverts when output < minimum
  // =========================================================

  function test_execute_call_revertsOnInsufficientOutput() public {
    uint256 amountIn = 0.1 ether;
    uint256 amountOut = 300e6;
    uint256 minAmountOut = 400e6; // higher than what mock returns

    setErc20Balance(USDC, address(swapRouter), amountOut);

    bytes memory swapCalldata = abi.encodeCall(MockVaultSwapRouter.swap, (WETH, USDC, amountIn, amountOut));
    swapCalldata = _signedSwapData(WETH, USDC, amountIn, minAmountOut, swapCalldata);
    bytes memory actionData = abi.encode(WETH, USDC, amountIn, minAmountOut, swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.execute(actions);
  }

  // =========================================================
  // minAmountOut = exact output passes
  // =========================================================

  function test_execute_call_exactMinAmountOutPasses() public {
    uint256 amountIn = 0.1 ether;
    uint256 amountOut = 300e6;

    setErc20Balance(USDC, address(swapRouter), amountOut);

    bytes memory swapCalldata = abi.encodeCall(MockVaultSwapRouter.swap, (WETH, USDC, amountIn, amountOut));
    swapCalldata = _signedSwapData(WETH, USDC, amountIn, amountOut, swapCalldata);
    // minAmountOut == amountOut exactly
    bytes memory actionData = abi.encode(WETH, USDC, amountIn, amountOut, swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vault.execute(actions); // should not revert
    assertEq(IERC20(USDC).balanceOf(address(vault)), 3000e6 + amountOut);
  }

  // =========================================================
  // Router not whitelisted: reverts InvalidSwapRouter
  // =========================================================

  function test_execute_call_revertsForNonWhitelistedRouter() public {
    address badRouter = makeAddr("badRouter");

    bytes memory actionData = abi.encode(WETH, USDC, uint256(0.1 ether), uint256(0), bytes(""));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(badRouter, actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, badRouter));
    vault.execute(actions);
  }

  // =========================================================
  // tokenIn is not a vault token: reverts TokenNotConfigured
  // =========================================================

  function test_execute_call_revertsForNonVaultTokenIn() public {
    address notVaultToken = makeAddr("notToken");

    bytes memory actionData = abi.encode(notVaultToken, USDC, uint256(100), uint256(0), bytes(""));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
  }

  // =========================================================
  // tokenOut is not a vault token: reverts TokenNotConfigured
  // =========================================================

  function test_execute_call_revertsForNonVaultTokenOut() public {
    address notVaultToken = makeAddr("notToken");

    bytes memory actionData = abi.encode(WETH, notVaultToken, uint256(0.1 ether), uint256(0), bytes(""));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
  }

  // =========================================================
  // Unauthorized caller cannot execute CALL actions
  // =========================================================

  function test_execute_call_revertsForUnauthorized() public {
    address attacker = makeAddr("attacker");

    bytes memory actionData = abi.encode(WETH, USDC, uint256(0.1 ether), uint256(0), bytes(""));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(attacker);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions);
  }

  // =========================================================
  // Whitelisted caller (not vault owner) can execute CALL
  // =========================================================

  function test_execute_call_allowsWhitelistedCaller() public {
    address whitelistedCaller = makeAddr("whitelistedCaller");

    // Whitelist the caller in configManager
    address[] memory callers = new address[](1);
    callers[0] = whitelistedCaller;
    vm.prank(vaultOwner);
    configManager.setWhitelistCallers(callers, true);

    uint256 amountIn = 0.1 ether;
    uint256 amountOut = 300e6;
    setErc20Balance(USDC, address(swapRouter), amountOut);

    bytes memory swapCalldata = abi.encodeCall(MockVaultSwapRouter.swap, (WETH, USDC, amountIn, amountOut));
    swapCalldata = _signedSwapData(WETH, USDC, amountIn, 0, swapCalldata);
    bytes memory actionData = abi.encode(WETH, USDC, amountIn, uint256(0), swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    // Whitelisted caller can execute
    vm.prank(whitelistedCaller);
    vault.execute(actions);

    assertEq(IERC20(USDC).balanceOf(address(vault)), 3000e6 + amountOut, "USDC should increase");
  }

  // =========================================================
  // Swap router call failure propagates revert
  // =========================================================

  function test_execute_call_revertsWhenRouterCallFails() public {
    // Pass calldata that will cause the mock router to revert (calling a nonexistent function)
    bytes memory badCalldata = abi.encodeWithSignature("nonexistentFunction()");
    badCalldata = _signedSwapData(WETH, USDC, 0.1 ether, 0, badCalldata);
    bytes memory actionData = abi.encode(WETH, USDC, uint256(0.1 ether), uint256(0), badCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.SwapFailed.selector, uint256(0)));
    vault.execute(actions);
  }

  // =========================================================
  // Vault paused: execute reverts
  // =========================================================

  function test_execute_call_revertsWhenVaultPaused() public {
    vm.prank(vaultOwner);
    vault.setPaused(true);

    bytes memory actionData = abi.encode(WETH, USDC, uint256(0.1 ether), uint256(0), bytes(""));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);

    vm.prank(vaultOwner);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
  }
}
