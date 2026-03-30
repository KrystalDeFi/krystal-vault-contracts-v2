// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedVaultAutomator } from "../../contracts/shared-vault/core/SharedVaultAutomator.sol";
import { ISharedVaultAutomator } from "../../contracts/shared-vault/interfaces/ISharedVaultAutomator.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";

// Mock ERC20 for tests
contract MockERC20 {
  string public name;
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name, string memory _symbol) {
    name = _name;
    symbol = _symbol;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// Mock swap target for swap operations
contract MockSwapTarget {
  function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
    MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    MockERC20(tokenOut).transfer(msg.sender, amountIn);
  }
}

// Mock strategy that records calls (via PositionChange return)
contract MockAutomatorStrategy is ISharedStrategy {
  function execute(bytes calldata) external payable override returns (PositionChange[] memory changes) {
    // Return an empty change set — execution is verified via vault.getPositionCount()
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }
}

// Expose internal EIP-712 helpers for test signing
contract SharedVaultAutomatorHelper is SharedVaultAutomator {
  constructor(address _owner, address[] memory _operators) SharedVaultAutomator(_owner, _operators) { }

  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return super._hashTypedDataV4(structHash);
  }
}

contract SharedVaultAutomatorTest is TestCommon {
  SharedVaultAutomatorHelper public automator;
  SharedVault public vault;
  SharedConfigManager public configManager;
  MockERC20 public tokenA;
  MockERC20 public tokenB;
  MockSwapTarget public swapTarget;
  MockAutomatorStrategy public mockStrategy;

  // Test accounts
  address public constant ADMIN = 0x1234567890123456789012345678901234567891;
  address public constant OPERATOR = 0x1234567890123456789012345678901234567892;
  address public constant NON_OPERATOR = 0x1234567890123456789012345678901234567893;

  // Signing keys
  uint256 public constant VAULT_OWNER_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
  address public immutable VAULT_OWNER;

  constructor() {
    VAULT_OWNER = vm.addr(VAULT_OWNER_KEY);
  }

  function setUp() public {
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");
    swapTarget = new MockSwapTarget();
    mockStrategy = new MockAutomatorStrategy();

    // Config manager
    configManager = new SharedConfigManager();
    address[] memory targets = new address[](2);
    targets[0] = address(mockStrategy);
    targets[1] = address(swapTarget);
    address[] memory callers = new address[](0);
    configManager.initialize(ADMIN, targets, callers, ADMIN);

    // Vault
    vault = new SharedVault();
    tokenA.mint(address(this), 1000e18);
    tokenB.mint(address(this), 1000e18);
    tokenA.transfer(address(vault), 100e18);
    tokenB.transfer(address(vault), 100e18);
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vault.initialize("Test Vault", vaultTokens, initialAmounts, VAULT_OWNER, address(configManager));

    // Automator
    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new SharedVaultAutomatorHelper(ADMIN, operators);

    // Whitelist the automator as a caller so it can call vault.execute/swap
    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();
  }

  // ─── Helper: build and sign an AgentAllowance ───────────────────────────

  uint256 private _nonce;

  function _agentAllowanceDigest(address _vault) internal returns (bytes32 digest, bytes memory encoded) {
    _nonce++;
    AgentAllowanceStructHash.AgentAllowance memory allowance = AgentAllowanceStructHash.AgentAllowance({
      vault: _vault,
      signatureTime: uint64(block.timestamp + _nonce),
      expirationTime: uint64(block.timestamp + 3600)
    });
    encoded = abi.encode(allowance);
    bytes32 structHash = AgentAllowanceStructHash._hash(encoded);
    digest = automator.hashTypedDataV4(structHash);
  }

  function _signAgentAllowance(address _vault)
    internal
    returns (bytes memory encoded, bytes memory sig)
  {
    (bytes32 digest, bytes memory enc) = _agentAllowanceDigest(_vault);
    encoded = enc;
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_OWNER_KEY, digest);
    sig = abi.encodePacked(r, s, v);
  }

  // ─── Helper: build and sign a user order (AgentAllowance, consumed on use) ──

  function _signUserOrder(address _vault)
    internal
    returns (bytes memory encoded, bytes memory sig)
  {
    // User orders use the same AgentAllowance struct; the contract enforces one-time use
    (bytes32 digest, bytes memory enc) = _agentAllowanceDigest(_vault);
    encoded = enc;
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_OWNER_KEY, digest);
    sig = abi.encodePacked(r, s, v);
  }

  // ─── Helper: build a single EXECUTE operation ───────────────────────────

  function _executeOp(bytes memory data) internal view returns (ISharedVaultAutomator.Operation[] memory ops) {
    ops = new ISharedVaultAutomator.Operation[](1);
    ops[0] = ISharedVaultAutomator.Operation({
      opType: ISharedVaultAutomator.OpType.EXECUTE,
      target: address(mockStrategy),
      data: data,
      value: 0
    });
  }

  // ─── Helper: build a single SWAP operation ──────────────────────────────

  function _swapOp(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (ISharedVaultAutomator.Operation[] memory ops) {
    bytes memory swapCall = abi.encodeWithSelector(MockSwapTarget.swap.selector, tokenIn, tokenOut, amountIn);
    bytes memory opData = abi.encode(tokenIn, tokenOut, amountIn, uint256(0), swapCall);
    ops = new ISharedVaultAutomator.Operation[](1);
    ops[0] = ISharedVaultAutomator.Operation({
      opType: ISharedVaultAutomator.OpType.SWAP,
      target: address(swapTarget),
      data: opData,
      value: 0
    });
  }

  // ============ Constructor tests ============

  function test_constructor_setsRoles() public view {
    assertTrue(automator.hasRole(automator.DEFAULT_ADMIN_ROLE(), ADMIN));
    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), ADMIN));
    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), OPERATOR));
  }

  // ============ executeWithAgentAllowance ============

  function test_executeWithAgentAllowance_success() public {
    (bytes memory encoded, bytes memory sig) = _signAgentAllowance(address(vault));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
    // No revert = success; strategy ran inside vault
  }

  function test_executeWithAgentAllowance_fail_nonOperator() public {
    (bytes memory encoded, bytes memory sig) = _signAgentAllowance(address(vault));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(NON_OPERATOR);
    vm.expectRevert();
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithAgentAllowance_fail_wrongVault() public {
    // Sign for a different vault address
    (bytes memory encoded, bytes memory sig) = _signAgentAllowance(address(0xDEAD));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithAgentAllowance_fail_expired() public {
    _nonce++;
    AgentAllowanceStructHash.AgentAllowance memory allowance = AgentAllowanceStructHash.AgentAllowance({
      vault: address(vault),
      signatureTime: uint64(block.timestamp),
      expirationTime: uint64(block.timestamp - 1) // already expired
    });
    bytes memory encoded = abi.encode(allowance);
    bytes32 structHash = AgentAllowanceStructHash._hash(encoded);
    bytes32 digest = automator.hashTypedDataV4(structHash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_OWNER_KEY, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithAgentAllowance_fail_wrongSigner() public {
    uint256 wrongKey = 0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF;
    _nonce++;
    AgentAllowanceStructHash.AgentAllowance memory allowance = AgentAllowanceStructHash.AgentAllowance({
      vault: address(vault),
      signatureTime: uint64(block.timestamp + _nonce),
      expirationTime: uint64(block.timestamp + 3600)
    });
    bytes memory encoded = abi.encode(allowance);
    bytes32 structHash = AgentAllowanceStructHash._hash(encoded);
    bytes32 digest = automator.hashTypedDataV4(structHash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithAgentAllowance_fail_cancelled() public {
    (bytes32 digest, bytes memory encoded) = _agentAllowanceDigest(address(vault));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_OWNER_KEY, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    // Cancel the order as the vault owner
    vm.prank(VAULT_OWNER);
    automator.cancelOrder(digest, sig);

    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    vm.expectRevert(ISharedVaultAutomator.OrderCancelled.selector);
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithAgentAllowance_fail_paused() public {
    (bytes memory encoded, bytes memory sig) = _signAgentAllowance(address(vault));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(ADMIN);
    automator.pause();

    vm.prank(OPERATOR);
    vm.expectRevert();
    automator.executeWithAgentAllowance(ISharedVault(address(vault)), ops, encoded, sig);
  }

  // ============ executeWithUserOrder ============

  function test_executeWithUserOrder_success() public {
    (bytes memory encoded, bytes memory sig) = _signUserOrder(address(vault));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    automator.executeWithUserOrder(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithUserOrder_onlyUsedOnce() public {
    (bytes memory encoded, bytes memory sig) = _signUserOrder(address(vault));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.startPrank(OPERATOR);
    automator.executeWithUserOrder(ISharedVault(address(vault)), ops, encoded, sig);

    // Second call must revert because order was consumed
    vm.expectRevert(ISharedVaultAutomator.OrderCancelled.selector);
    automator.executeWithUserOrder(ISharedVault(address(vault)), ops, encoded, sig);
    vm.stopPrank();
  }

  function test_executeWithUserOrder_fail_wrongVault() public {
    (bytes memory encoded, bytes memory sig) = _signUserOrder(address(0xDEAD));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.executeWithUserOrder(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithUserOrder_fail_nonOperator() public {
    (bytes memory encoded, bytes memory sig) = _signUserOrder(address(vault));
    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(NON_OPERATOR);
    vm.expectRevert();
    automator.executeWithUserOrder(ISharedVault(address(vault)), ops, encoded, sig);
  }

  function test_executeWithUserOrder_fail_cancelledManually() public {
    (bytes32 digest, bytes memory encoded) = _agentAllowanceDigest(address(vault));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_OWNER_KEY, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    vm.prank(VAULT_OWNER);
    automator.cancelOrder(digest, sig);

    ISharedVaultAutomator.Operation[] memory ops = _executeOp(abi.encode(uint256(0)));

    vm.prank(OPERATOR);
    vm.expectRevert(ISharedVaultAutomator.OrderCancelled.selector);
    automator.executeWithUserOrder(ISharedVault(address(vault)), ops, encoded, sig);
  }

  // ============ cancelOrder ============

  function test_cancelOrder_success() public {
    (bytes32 digest,) = _agentAllowanceDigest(address(vault));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_OWNER_KEY, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    assertFalse(automator.isOrderCancelled(sig));

    vm.prank(VAULT_OWNER);
    automator.cancelOrder(digest, sig);

    assertTrue(automator.isOrderCancelled(sig));
  }

  function test_cancelOrder_fail_wrongSigner() public {
    (bytes32 digest,) = _agentAllowanceDigest(address(vault));
    // Sign with a different key than the expected signer
    uint256 wrongKey = 0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF;
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
    bytes memory sig = abi.encodePacked(r, s, v);

    // VAULT_OWNER tries to cancel a sig they didn't make
    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedVaultAutomator.InvalidSignature.selector);
    automator.cancelOrder(digest, sig);
  }

  // ============ grantOperator / revokeOperator ============

  function test_grantOperator_success() public {
    assertFalse(automator.hasRole(automator.OPERATOR_ROLE_HASH(), NON_OPERATOR));

    vm.prank(ADMIN);
    automator.grantOperator(NON_OPERATOR);

    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), NON_OPERATOR));
  }

  function test_revokeOperator_success() public {
    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), OPERATOR));

    vm.prank(ADMIN);
    automator.revokeOperator(OPERATOR);

    assertFalse(automator.hasRole(automator.OPERATOR_ROLE_HASH(), OPERATOR));
  }

  function test_grantOperator_fail_nonAdmin() public {
    vm.prank(NON_OPERATOR);
    vm.expectRevert();
    automator.grantOperator(NON_OPERATOR);
  }

  // ============ pause / unpause ============

  function test_pause_unpause() public {
    assertFalse(automator.paused());

    vm.prank(ADMIN);
    automator.pause();
    assertTrue(automator.paused());

    vm.prank(ADMIN);
    automator.unpause();
    assertFalse(automator.paused());
  }

  function test_pause_fail_nonAdmin() public {
    vm.prank(NON_OPERATOR);
    vm.expectRevert();
    automator.pause();
  }

  // ============ ETH validation ============

  function test_executeWithAgentAllowance_fail_ethMismatch() public {
    (bytes memory encoded, bytes memory sig) = _signAgentAllowance(address(vault));

    // Op says it needs 1 ether but we send 0
    ISharedVaultAutomator.Operation[] memory ops = new ISharedVaultAutomator.Operation[](1);
    ops[0] = ISharedVaultAutomator.Operation({
      opType: ISharedVaultAutomator.OpType.EXECUTE,
      target: address(mockStrategy),
      data: abi.encode(uint256(0)),
      value: 1 ether
    });

    vm.deal(OPERATOR, 0);
    vm.prank(OPERATOR);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    automator.executeWithAgentAllowance{ value: 0 }(ISharedVault(address(vault)), ops, encoded, sig);
  }
}
