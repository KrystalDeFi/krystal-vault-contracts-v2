// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { PrivateVaultAutomator } from "../../contracts/private-vault/core/PrivateVaultAutomator.sol";
import { IPrivateVaultAutomator } from "../../contracts/private-vault/interfaces/core/IPrivateVaultAutomator.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// Mock strategy contract for testing
contract MockStrategy {
  uint256 public value;
  bool public shouldFail;

  function setValue(uint256 _value) external {
    if (shouldFail) revert("Strategy call failed");
    value = _value;
  }

  function getValue() external view returns (uint256) {
    return value;
  }

  function setShouldFail(bool _shouldFail) external {
    shouldFail = _shouldFail;
  }

  function fail() external pure {
    revert("Strategy call failed");
  }
}

// Mock ERC20 token for testing
contract MockERC20 {
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

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
    require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    allowance[from][msg.sender] -= amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

contract PrivateVaultAutomatorTest is TestCommon {
  PrivateVaultAutomator public automator;
  PrivateVault public privateVault;
  PrivateConfigManager public configManager;
  MockStrategy public mockStrategy;
  MockERC20 public mockERC20;

  // Test addresses
  address public constant OPERATOR = 0x1234567890123456789012345678901234567891;
  address public constant NON_OPERATOR = 0x1234567890123456789012345678901234567892;
  address public constant ADMIN = 0x1234567890123456789012345678901234567893;

  // Private keys for signing
  uint256 public constant VAULT_OWNER_PRIVATE_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
  uint256 public constant OPERATOR_PRIVATE_KEY = 0x9876543210987654321098765432109876543210987654321098765432109876;

  // Derived addresses from private keys
  address public immutable VAULT_OWNER;

  constructor() {
    VAULT_OWNER = vm.addr(VAULT_OWNER_PRIVATE_KEY);
  }

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    // Deploy mock contracts
    mockStrategy = new MockStrategy();
    mockERC20 = new MockERC20();

    // Deploy config manager
    configManager = new PrivateConfigManager();

    // Initialize config manager
    address[] memory whitelistTargets = new address[](1);
    whitelistTargets[0] = address(mockStrategy);
    address[] memory whitelistCallers = new address[](0);

    configManager.initialize(ADMIN, whitelistTargets, whitelistCallers);

    // Deploy private vault
    privateVault = new PrivateVault();
    privateVault.initialize(VAULT_OWNER, address(configManager));

    // Deploy automator with owner and operators
    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new PrivateVaultAutomator(ADMIN, operators);

    // Whitelist the automator in the config manager
    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();
  }

  // ============ HELPER FUNCTIONS ============

  function _createAutomationOrder(address strategy, uint256 nonce, uint256 deadline) internal pure returns (bytes32) {
    // Create a structured message for "Allow automation on strategy X"
    return
      keccak256(abi.encodePacked("Allow automation on strategy ", strategy, " nonce: ", nonce, " deadline: ", deadline));
  }

  function _signMessage(bytes32 messageHash, uint256 privateKey) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
    return abi.encodePacked(r, s, v);
  }

  function _createMulticallData()
    internal
    pure
    returns (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes)
  {
    targets = new address[](1);
    targets[0] = address(0); // Will be set in tests

    data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    return (targets, data, callTypes);
  }

  // ============ CONSTRUCTOR TESTS ============

  function test_constructor_setsRolesCorrectly() public view {
    assertTrue(automator.hasRole(automator.DEFAULT_ADMIN_ROLE(), ADMIN));
    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), ADMIN));
    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), OPERATOR));
  }

  function test_constructor_grantsMultipleOperators() public {
    address[] memory operators = new address[](2);
    operators[0] = OPERATOR;
    operators[1] = NON_OPERATOR;

    PrivateVaultAutomator newAutomator = new PrivateVaultAutomator(ADMIN, operators);

    assertTrue(newAutomator.hasRole(newAutomator.DEFAULT_ADMIN_ROLE(), ADMIN));
    assertTrue(newAutomator.hasRole(newAutomator.OPERATOR_ROLE_HASH(), ADMIN));
    assertTrue(newAutomator.hasRole(newAutomator.OPERATOR_ROLE_HASH(), OPERATOR));
    assertTrue(newAutomator.hasRole(newAutomator.OPERATOR_ROLE_HASH(), NON_OPERATOR));
  }

  // ============ EXECUTE MULTICALL TESTS ============

  function test_executeMulticall_success() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Execute multicall as operator
    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();

    // Verify the strategy was called
    assertEq(mockStrategy.getValue(), 42);
  }

  function test_executeMulticall_fail_unauthorizedOperator() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Try to execute as non-operator
    vm.startPrank(NON_OPERATOR);
    vm.expectRevert();
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();
  }

  function test_executeMulticall_fail_invalidSignature() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory invalidSignature = _signMessage(orderHash, OPERATOR_PRIVATE_KEY); // Wrong signer

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Try to execute with invalid signature
    vm.startPrank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticall(
      IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, invalidSignature
    );
    vm.stopPrank();
  }

  function test_executeMulticall_fail_cancelledOrder() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Cancel the order first
    vm.startPrank(VAULT_OWNER);
    automator.cancelOrder(orderHash, signature);
    vm.stopPrank();

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Try to execute cancelled order
    vm.startPrank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.OrderCancelled.selector);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();
  }

  function test_executeMulticall_fail_whenPaused() public {
    // Pause the automator
    vm.startPrank(ADMIN);
    automator.pause();
    vm.stopPrank();

    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Try to execute when paused
    vm.startPrank(OPERATOR);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();
  }

  function test_executeMulticall_multipleCalls() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Prepare multicall data with multiple calls
    address[] memory targets = new address[](2);
    targets[0] = address(mockStrategy);
    targets[1] = address(mockStrategy);

    bytes[] memory data = new bytes[](2);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 100);
    data[1] = abi.encodeWithSelector(MockStrategy.setValue.selector, 200);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);
    callTypes[0] = IPrivateCommon.CallType.CALL;
    callTypes[1] = IPrivateCommon.CallType.CALL;

    // Execute multicall as operator
    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();

    // Verify the last call was executed
    assertEq(mockStrategy.getValue(), 200);
  }

  //   function test_executeMulticall_delegateCall() public {
  //     // Create automation order
  //     bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
  //     bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

  //     // Prepare multicall data with delegatecall
  //     address[] memory targets = new address[](1);
  //     targets[0] = address(mockStrategy);

  //     bytes[] memory data = new bytes[](1);
  //     data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 300);

  //     IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
  //     callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

  //     vm.startPrank(OPERATOR);
  //     automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash,
  // signature);
  //     vm.stopPrank();

  //     assertEq(mockStrategy.getValue(), 300);
  //   }

  // ============ ORDER CANCELLATION TESTS ============

  function test_cancelOrder_success() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Cancel the order
    vm.startPrank(VAULT_OWNER);
    vm.expectEmit(true, true, true, true);
    emit IPrivateVaultAutomator.CancelOrder(VAULT_OWNER, orderHash, signature);
    automator.cancelOrder(orderHash, signature);
    vm.stopPrank();

    // Verify order is cancelled
    assertTrue(automator.isOrderCancelled(signature));
  }

  function test_cancelOrder_fail_invalidSignature() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory invalidSignature = _signMessage(orderHash, OPERATOR_PRIVATE_KEY); // Wrong signer

    // Try to cancel with invalid signature
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.cancelOrder(orderHash, invalidSignature);
    vm.stopPrank();
  }

  function test_cancelOrder_fail_wrongSigner() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Try to cancel as wrong signer
    vm.startPrank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.cancelOrder(orderHash, signature);
    vm.stopPrank();
  }

  function test_isOrderCancelled_notCancelled() public view {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Verify order is not cancelled
    assertFalse(automator.isOrderCancelled(signature));
  }

  function test_isOrderCancelled_cancelled() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Cancel the order
    vm.startPrank(VAULT_OWNER);
    automator.cancelOrder(orderHash, signature);
    vm.stopPrank();

    // Verify order is cancelled
    assertTrue(automator.isOrderCancelled(signature));
  }

  // ============ ROLE MANAGEMENT TESTS ============

  function test_grantOperator_success() public {
    address newOperator = address(0x999);

    vm.startPrank(ADMIN);
    automator.grantOperator(newOperator);
    vm.stopPrank();

    assertTrue(automator.hasRole(automator.OPERATOR_ROLE_HASH(), newOperator));
  }

  function test_grantOperator_fail_unauthorized() public {
    address newOperator = address(0x999);

    vm.startPrank(OPERATOR);
    vm.expectRevert();
    automator.grantOperator(newOperator);
    vm.stopPrank();
  }

  function test_revokeOperator_success() public {
    vm.startPrank(ADMIN);
    automator.revokeOperator(OPERATOR);
    vm.stopPrank();

    assertFalse(automator.hasRole(automator.OPERATOR_ROLE_HASH(), OPERATOR));
  }

  function test_revokeOperator_fail_unauthorized() public {
    vm.startPrank(OPERATOR);
    vm.expectRevert();
    automator.revokeOperator(OPERATOR);
    vm.stopPrank();
  }

  // ============ PAUSE TESTS ============

  function test_pause_success() public {
    vm.startPrank(ADMIN);
    automator.pause();
    vm.stopPrank();

    assertTrue(automator.paused());
  }

  function test_pause_fail_unauthorized() public {
    vm.startPrank(OPERATOR);
    vm.expectRevert();
    automator.pause();
    vm.stopPrank();
  }

  function test_unpause_success() public {
    // First pause
    vm.startPrank(ADMIN);
    automator.pause();
    vm.stopPrank();

    // Then unpause
    vm.startPrank(ADMIN);
    automator.unpause();
    vm.stopPrank();

    assertFalse(automator.paused());
  }

  function test_unpause_fail_unauthorized() public {
    // First pause
    vm.startPrank(ADMIN);
    automator.pause();
    vm.stopPrank();

    // Try to unpause as non-admin
    vm.startPrank(OPERATOR);
    vm.expectRevert();
    automator.unpause();
    vm.stopPrank();
  }

  // ============ RECEIVE FUNCTION TESTS ============

  function test_receive_native_tokens() public {
    uint256 initialBalance = address(automator).balance;

    vm.deal(address(this), 1 ether);
    (bool success,) = address(automator).call{ value: 1 ether }("");
    assertTrue(success);

    assertEq(address(automator).balance, initialBalance + 1 ether);
  }

  // ============ INTERFACE SUPPORT TESTS ============

  function test_supportsInterface() public view {
    // Test AccessControl interface
    assertTrue(automator.supportsInterface(0x7965db0b));
    // Test Pausable interface (if it has one)
    // Note: Pausable doesn't have a standard interface ID, so we test the function exists
  }

  // ============ EDGE CASE TESTS ============

  function test_executeMulticall_emptyTargets() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Prepare empty multicall data
    address[] memory targets = new address[](0);
    bytes[] memory data = new bytes[](0);
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](0);

    // Execute multicall as operator
    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();

    // Should succeed with empty arrays
  }

  function test_executeMulticall_zeroAddressTarget() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(0), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Prepare multicall data with zero address target
    address[] memory targets = new address[](1);
    targets[0] = address(0);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Execute multicall as operator
    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();

    // Should succeed (zero address targets are skipped in the vault)
  }

  function test_executeMulticall_strategyCallFails() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Make strategy fail
    mockStrategy.setShouldFail(true);

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Execute multicall as operator - should fail due to strategy failure
    vm.startPrank(OPERATOR);
    vm.expectRevert();
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();
  }

  function test_executeMulticall_differentOrderHash() public {
    // Create automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // Use different order hash
    bytes32 differentOrderHash = _createAutomationOrder(address(mockStrategy), 2, block.timestamp + 3600);

    // Prepare multicall data
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    // Execute multicall as operator with different hash
    vm.startPrank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticall(
      IPrivateVault(address(privateVault)), targets, data, callTypes, differentOrderHash, signature
    );
    vm.stopPrank();
  }

  // ============ INTEGRATION TESTS ============

  function test_fullAutomationFlow() public {
    // 1. Vault owner creates automation order
    bytes32 orderHash = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes memory signature = _signMessage(orderHash, VAULT_OWNER_PRIVATE_KEY);

    // 2. Verify order is not cancelled
    assertFalse(automator.isOrderCancelled(signature));

    // 3. Operator executes multicall
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();

    // 4. Verify strategy was executed
    assertEq(mockStrategy.getValue(), 42);

    // 5. Vault owner cancels the order
    vm.startPrank(VAULT_OWNER);
    automator.cancelOrder(orderHash, signature);
    vm.stopPrank();

    // 6. Verify order is cancelled
    assertTrue(automator.isOrderCancelled(signature));

    // 7. Try to execute again - should fail
    vm.startPrank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.OrderCancelled.selector);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash, signature);
    vm.stopPrank();
  }

  function test_multipleOrdersSameStrategy() public {
    // Create multiple orders for the same strategy
    bytes32 orderHash1 = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes32 orderHash2 = _createAutomationOrder(address(mockStrategy), 2, block.timestamp + 3600);

    bytes memory signature1 = _signMessage(orderHash1, VAULT_OWNER_PRIVATE_KEY);
    bytes memory signature2 = _signMessage(orderHash2, VAULT_OWNER_PRIVATE_KEY);

    // Execute first order
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash1, signature1);
    vm.stopPrank();

    assertEq(mockStrategy.getValue(), 42);

    // Cancel first order
    vm.startPrank(VAULT_OWNER);
    automator.cancelOrder(orderHash1, signature1);
    vm.stopPrank();

    // Execute second order
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 100);

    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash2, signature2);
    vm.stopPrank();

    assertEq(mockStrategy.getValue(), 100);
  }

  function test_orderWithDifferentStrategies() public {
    MockStrategy strategy2 = new MockStrategy();

    // Whitelist second strategy
    vm.startPrank(ADMIN);
    address[] memory strategies = new address[](1);
    strategies[0] = address(strategy2);
    configManager.setWhitelistTargets(strategies, true);
    vm.stopPrank();

    // Create orders for different strategies
    bytes32 orderHash1 = _createAutomationOrder(address(mockStrategy), 1, block.timestamp + 3600);
    bytes32 orderHash2 = _createAutomationOrder(address(strategy2), 1, block.timestamp + 3600);

    bytes memory signature1 = _signMessage(orderHash1, VAULT_OWNER_PRIVATE_KEY);
    bytes memory signature2 = _signMessage(orderHash2, VAULT_OWNER_PRIVATE_KEY);

    // Execute first order
    (address[] memory targets, bytes[] memory data, IPrivateCommon.CallType[] memory callTypes) = _createMulticallData();
    targets[0] = address(mockStrategy);

    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash1, signature1);
    vm.stopPrank();

    assertEq(mockStrategy.getValue(), 42);

    // Execute second order
    targets[0] = address(strategy2);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 200);

    vm.startPrank(OPERATOR);
    automator.executeMulticall(IPrivateVault(address(privateVault)), targets, data, callTypes, orderHash2, signature2);
    vm.stopPrank();

    assertEq(strategy2.getValue(), 200);
    assertEq(mockStrategy.getValue(), 42); // First strategy unchanged
  }
}
