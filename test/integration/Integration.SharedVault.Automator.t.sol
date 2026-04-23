// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, WETH, USDC, NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedVaultAutomator } from "../../contracts/shared-vault/interfaces/ISharedVaultAutomator.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedVaultAutomator } from "../../contracts/shared-vault/core/SharedVaultAutomator.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

import { AgentAllowanceStructHash } from "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

// ─── Mock swap router ─────────────────────────────────────────────────────────

/// @dev Mock router for automator CALL-type actions.
contract MockAutomatorSwapRouter {
  using SafeERC20 for IERC20;

  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
  }
}

// ─── Test contract ────────────────────────────────────────────────────────────

contract SharedVaultAutomatorIntegrationTest is TestCommon {
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedVault public vaultImplementation;
  LpFeeTaker public lpFeeTaker;
  SharedV3Strategy public v3Strategy;
  SharedVault public vault;
  SharedVaultAutomator public automator;
  MockAutomatorSwapRouter public swapRouter;

  // Vault owner has a known private key — needed to sign EIP-712 authorization structs
  uint256 public vaultOwnerPk;
  address public vaultOwner;
  address public operator;
  address public feeRecipient;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 36_953_600);
    vm.selectFork(fork);

    (vaultOwner, vaultOwnerPk) = makeAddrAndKey("vaultOwner");
    operator = makeAddr("operator");
    feeRecipient = makeAddr("feeRecipient");
    swapRouter = new MockAutomatorSwapRouter();

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);
    vm.deal(vaultOwner, 100 ether);

    vm.startPrank(vaultOwner);

    lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));

    // Deploy automator — owner + operator can execute
    address[] memory operators = new address[](1);
    operators[0] = operator;
    automator = new SharedVaultAutomator(vaultOwner, operators);

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM;
    address[] memory routers = new address[](1);
    routers[0] = address(swapRouter);
    // Whitelist automator as a vault caller so vault.execute() accepts it
    address[] memory callers = new address[](1);
    callers[0] = address(automator);

    configManager = new SharedConfigManager();
    configManager.initialize(vaultOwner, targets, callers, feeRecipient, 0, nfpms, routers);

    vaultImplementation = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(vaultImplementation), WETH);

    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    IERC20(USDC).approve(address(vaultFactory), 3000e6);
    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(1 ether), 3000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-Automator-Test", vaultTokens, initialAmounts, 0)));

    vm.stopPrank();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// @dev Build and sign an AgentAllowance. Returns encoded struct + signature.
  function _signAgentAllowance(
    uint256 signerPk,
    address vaultAddr,
    uint64 expirationTime
  ) internal view returns (bytes memory encodedAA, bytes memory sig) {
    AgentAllowanceStructHash.AgentAllowance memory aa = AgentAllowanceStructHash.AgentAllowance({
      vault: vaultAddr,
      signatureTime: uint64(block.timestamp),
      expirationTime: expirationTime
    });
    encodedAA = abi.encode(aa);

    bytes32 structHash = AgentAllowanceStructHash._hash(encodedAA);
    bytes32 digest = keccak256(abi.encodePacked(bytes2("\x19\x01"), automator.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
    sig = abi.encodePacked(r, s, v);
  }

  /// @dev Build and sign a minimal Order. Returns encoded struct + signature.
  function _signOrder(uint256 signerPk) internal view returns (bytes memory encodedOrder, bytes memory sig) {
    // Build a zero-initialized OrderConfig; all string fields default to ""
    StructHash.OrderConfig memory config;

    StructHash.Order memory order = StructHash.Order({
      chainId: int64(int256(block.chainid)),
      nfpmAddress: NFPM,
      tokenId: 0,
      orderType: "AutoCompound",
      config: config,
      signatureTime: int64(int256(block.timestamp))
    });
    encodedOrder = abi.encode(order);

    bytes32 structHash = StructHash._hash(encodedOrder);
    bytes32 digest = keccak256(abi.encodePacked(bytes2("\x19\x01"), automator.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
    sig = abi.encodePacked(r, s, v);
  }

  /// @dev Build a CALL-type action that swaps amountIn WETH for amountOut USDC via the mock router.
  function _buildSwapAction(uint256 amountIn, uint256 amountOut) internal view returns (ISharedVault.Action memory) {
    bytes memory swapCalldata = abi.encodeCall(MockAutomatorSwapRouter.swap, (WETH, USDC, amountIn, amountOut));
    bytes memory actionData = abi.encode(WETH, USDC, amountIn, uint256(0), swapCalldata);
    return ISharedVault.Action(address(swapRouter), actionData, ISharedCommon.CallType.CALL);
  }

  // =========================================================
  // executeWithAgentAllowance: happy path executes vault CALL
  // =========================================================

  function test_executeWithAgentAllowance_executesVaultAction() public {
    uint256 amountIn = 0.1 ether;
    uint256 amountOut = 300e6;
    setErc20Balance(USDC, address(swapRouter), amountOut);

    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = _buildSwapAction(amountIn, amountOut);

    uint256 usdcBefore = IERC20(USDC).balanceOf(address(vault));

    vm.prank(operator);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);

    assertEq(IERC20(USDC).balanceOf(address(vault)), usdcBefore + amountOut, "vault USDC should increase");
    console.log("executeWithAgentAllowance: vault USDC gained =", amountOut);
  }

  // =========================================================
  // executeWithAgentAllowance: expired allowance reverts
  // =========================================================

  function test_executeWithAgentAllowance_revertsForExpiredAllowance() public {
    // Sign with expiration in the past
    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp - 1) // expired
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  // =========================================================
  // executeWithAgentAllowance: wrong signer reverts
  // =========================================================

  function test_executeWithAgentAllowance_revertsForWrongSigner() public {
    // Sign with a different private key (not vault owner)
    (, uint256 wrongPk) = makeAddrAndKey("wrongSigner");

    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      wrongPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  // =========================================================
  // executeWithAgentAllowance: wrong vault address in allowance reverts
  // =========================================================

  function test_executeWithAgentAllowance_revertsForWrongVault() public {
    address wrongVault = makeAddr("wrongVault");

    // Sign a valid allowance for a different vault address
    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      wrongVault, // not our vault
      uint64(block.timestamp + 1 hours)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  // =========================================================
  // executeWithAgentAllowance: non-operator caller reverts
  // =========================================================

  function test_executeWithAgentAllowance_revertsForNonOperator() public {
    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    address attacker = makeAddr("attacker");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(attacker);
    vm.expectRevert(); // AccessControl revert
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  // =========================================================
  // executeWithUserOrder: happy path executes vault action
  // =========================================================

  function test_executeWithUserOrder_executesVaultAction() public {
    uint256 amountIn = 0.1 ether;
    uint256 amountOut = 300e6;
    setErc20Balance(USDC, address(swapRouter), amountOut);

    (bytes memory encodedOrder, bytes memory sig) = _signOrder(vaultOwnerPk);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = _buildSwapAction(amountIn, amountOut);

    uint256 usdcBefore = IERC20(USDC).balanceOf(address(vault));

    vm.prank(operator);
    automator.executeWithUserOrder(ISharedVault(address(vault)), actions, encodedOrder, sig);

    assertEq(IERC20(USDC).balanceOf(address(vault)), usdcBefore + amountOut, "vault USDC should increase");
    console.log("executeWithUserOrder: vault USDC gained =", amountOut);
  }

  // =========================================================
  // executeWithUserOrder: wrong signer reverts
  // =========================================================

  function test_executeWithUserOrder_revertsForWrongSigner() public {
    (, uint256 wrongPk) = makeAddrAndKey("wrongSigner");
    (bytes memory encodedOrder, bytes memory sig) = _signOrder(wrongPk);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithUserOrder(ISharedVault(address(vault)), actions, encodedOrder, sig);
  }

  // =========================================================
  // cancelOrder: prevents future execution of that allowance
  // =========================================================

  function test_cancelOrder_preventsAgentAllowanceExecution() public {
    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    // Vault owner cancels the allowance digest
    bytes32 structHash = AgentAllowanceStructHash._hash(encodedAA);
    bytes32 digest = keccak256(abi.encodePacked(bytes2("\x19\x01"), automator.DOMAIN_SEPARATOR(), structHash));

    vm.prank(vaultOwner);
    automator.cancelOrder(digest, sig);

    assertTrue(automator.isOrderCancelled(digest), "order should be cancelled");

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(ISharedVaultAutomator.OrderCancelled.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  // =========================================================
  // cancelOrder: prevents future execution of that user order
  // =========================================================

  function test_cancelOrder_preventsUserOrderExecution() public {
    (bytes memory encodedOrder, bytes memory sig) = _signOrder(vaultOwnerPk);

    bytes32 structHash = StructHash._hash(encodedOrder);
    bytes32 digest = keccak256(abi.encodePacked(bytes2("\x19\x01"), automator.DOMAIN_SEPARATOR(), structHash));

    vm.prank(vaultOwner);
    automator.cancelOrder(digest, sig);

    assertTrue(automator.isOrderCancelled(digest), "order should be cancelled");

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(ISharedVaultAutomator.OrderCancelled.selector);
    automator.executeWithUserOrder(ISharedVault(address(vault)), actions, encodedOrder, sig);
  }

  // =========================================================
  // grantOperator / revokeOperator: role management
  // =========================================================

  function test_grantOperator_allowsNewOperatorToExecute() public {
    address newOperator = makeAddr("newOperator");

    vm.prank(vaultOwner);
    automator.grantOperator(newOperator);

    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    // New operator can now execute
    vm.prank(newOperator);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  function test_revokeOperator_preventsRevokedOperatorFromExecuting() public {
    // Revoke existing operator
    vm.prank(vaultOwner);
    automator.revokeOperator(operator);

    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(); // AccessControl revert
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }

  // =========================================================
  // Automator paused: execute reverts
  // =========================================================

  function test_executeWithAgentAllowance_revertsWhenAutomatorPaused() public {
    vm.prank(vaultOwner);
    automator.pause();

    (bytes memory encodedAA, bytes memory sig) = _signAgentAllowance(
      vaultOwnerPk,
      address(vault),
      uint64(block.timestamp + 1 hours)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(operator);
    vm.expectRevert(); // Pausable revert
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), actions, encodedAA, sig);
  }
}
