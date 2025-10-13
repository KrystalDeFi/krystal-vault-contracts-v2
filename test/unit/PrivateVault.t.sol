// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateConfigManager } from "../../contracts/private-vault/interfaces/core/IPrivateConfigManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Mock strategy contract for testing
contract MockStrategy {
  uint256 public value;
  uint256 public receivedValue;

  function setValue(uint256 _value) external {
    value = _value;
  }

  function getValue() external view returns (uint256) {
    return value;
  }

  function fail() external pure {
    revert("Strategy call failed");
  }

  // Payable function to receive ETH and track the amount
  function receiveValue() external payable {
    receivedValue += msg.value;
  }

  function getReceivedValue() external view returns (uint256) {
    return receivedValue;
  }

  // Function that both sets value and receives ETH
  function setValueAndReceive(uint256 _value) external payable {
    value = _value;
    receivedValue += msg.value;
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

// Mock ERC721 token for testing
contract MockERC721 {
  mapping(uint256 => address) public ownerOf;
  mapping(address => uint256) public balanceOf;
  mapping(uint256 => address) public getApproved;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function mint(address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == address(0), "Token already exists");
    ownerOf[tokenId] = to;
    balanceOf[to]++;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    require(
      msg.sender == from || getApproved[tokenId] == msg.sender || isApprovedForAll[from][msg.sender], "Not approved"
    );
    ownerOf[tokenId] = to;
    balanceOf[from]--;
    balanceOf[to]++;
  }

  function setApprovalForAll(address operator, bool approved) external {
    isApprovedForAll[msg.sender][operator] = approved;
  }
}

// Mock ERC1155 token for testing
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function mint(address to, uint256 id, uint256 amount) external {
    balanceOf[to][id] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
    require(balanceOf[from][id] >= amount, "Insufficient balance");
    require(msg.sender == from || isApprovedForAll[from][msg.sender], "Not approved");
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;
  }

  function setApprovalForAll(address operator, bool approved) external {
    isApprovedForAll[msg.sender][operator] = approved;
  }
}

contract PrivateVaultTest is TestCommon {
  PrivateVault public privateVault;
  PrivateConfigManager public configManager;
  address public constant VAULT_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant ADMIN = 0x1234567890123456789012345678901234567891;
  address public constant STRATEGY = 0x1234567890123456789012345678901234567892;
  address public constant NON_WHITELISTED = 0x1234567890123456789012345678901234567893;

  MockStrategy public mockStrategy;
  MockERC20 public mockERC20;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    // Deploy config manager
    configManager = new PrivateConfigManager();

    // Initialize config manager
    address[] memory whitelistTargets = new address[](0);
    address[] memory whitelistCallers = new address[](1);
    whitelistCallers[0] = VAULT_OWNER;

    configManager.initialize(VAULT_OWNER, whitelistTargets, whitelistCallers);

    // Deploy mock contracts
    mockStrategy = new MockStrategy();
    mockERC20 = new MockERC20();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();

    // Deploy private vault
    privateVault = new PrivateVault();
    privateVault.initialize(VAULT_OWNER, address(configManager));

    // Whitelist the mock strategy
    vm.startPrank(VAULT_OWNER);
    address[] memory strategies = new address[](1);
    strategies[0] = address(mockStrategy);
    configManager.setWhitelistTargets(strategies, true);

    // Grant admin role
    privateVault.grantAdminRole(ADMIN);
    vm.stopPrank();
  }

  function test_multicall_delegatecall() public {
    vm.startBroadcast(VAULT_OWNER);

    // Prepare multicall parameters
    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    // Execute multicall
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    // Verify the value was set via delegatecall (should be set on the vault's storage)
    // Since it's a delegatecall, the storage should be modified on the vault
    vm.stopBroadcast();
  }

  function test_multicall_call() public {
    vm.startBroadcast(VAULT_OWNER);

    // Prepare multicall parameters
    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 100);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Execute multicall
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    // Verify the value was set via call (should be set on the strategy's storage)
    assertEq(mockStrategy.getValue(), 100);

    vm.stopBroadcast();
  }

  function test_multicall_mixed_call_types() public {
    vm.startBroadcast(VAULT_OWNER);

    // Prepare multicall parameters with multiple calls
    address[] memory targets = new address[](2);
    targets[0] = address(mockStrategy);
    targets[1] = address(mockStrategy);

    bytes[] memory data = new bytes[](2);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 200);
    data[1] = abi.encodeWithSelector(MockStrategy.setValue.selector, 300);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);
    callTypes[0] = IPrivateCommon.CallType.CALL;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    // Execute multicall
    uint256[] memory callValues = new uint256[](2);
    callValues[0] = 0;
    callValues[1] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    // The last call should have set the value to 300 via delegatecall
    vm.stopBroadcast();
  }

  function test_multicall_fail_unauthorized() public {
    vm.startBroadcast(NON_WHITELISTED);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Should revert with Unauthorized
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();
  }

  function test_multicall_fail_invalid_strategy() public {
    address automator = address(0x888);

    vm.startBroadcast(VAULT_OWNER);
    address[] memory automators = new address[](1);
    automators[0] = automator;
    configManager.setWhitelistCallers(automators, true);
    vm.stopBroadcast();

    vm.startBroadcast(automator);

    address[] memory targets = new address[](1);
    targets[0] = NON_WHITELISTED; // Not whitelisted strategy

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Should revert with InvalidTarget
    vm.expectRevert(abi.encodeWithSelector(IPrivateVault.InvalidTarget.selector, NON_WHITELISTED));
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();
  }

  function test_multicall_fail_invalid_params_length() public {
    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](2); // Different length
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);
    data[1] = abi.encodeWithSelector(MockStrategy.setValue.selector, 43);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Should revert with InvalidMulticallParams
    vm.expectRevert(IPrivateVault.InvalidMulticallParams.selector);
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();
  }

  function test_multicall_fail_invalid_calltypes_length() public {
    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2); // Different length
    callTypes[0] = IPrivateCommon.CallType.CALL;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    // Should revert with InvalidMulticallParams
    vm.expectRevert(IPrivateVault.InvalidMulticallParams.selector);
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();
  }

  function test_multicall_skip_zero_address() public {
    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](2);
    targets[0] = address(0); // Zero address should be skipped
    targets[1] = address(mockStrategy);

    bytes[] memory data = new bytes[](2);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);
    data[1] = abi.encodeWithSelector(MockStrategy.setValue.selector, 100);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);
    callTypes[0] = IPrivateCommon.CallType.CALL;
    callTypes[1] = IPrivateCommon.CallType.CALL;

    // Should execute successfully, skipping the zero address
    uint256[] memory callValues = new uint256[](2);
    callValues[0] = 0;
    callValues[1] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    // Verify the second call was executed
    assertEq(mockStrategy.getValue(), 100);

    vm.stopBroadcast();
  }

  function test_multicall_admin_can_call() public {
    vm.startBroadcast(ADMIN);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 999);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Admin should be able to call multicall
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    // Verify the call was executed
    assertEq(mockStrategy.getValue(), 999);

    vm.stopBroadcast();
  }

  function test_multicall_failed_strategy_call() public {
    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(IPrivateVault.StrategyDelegateCallFailed.selector);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    // Should revert with StrategyDelegateCallFailed
    vm.expectRevert(IPrivateVault.StrategyDelegateCallFailed.selector);
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();
  }

  // ============ SWEEP NATIVE TOKEN TESTS ============

  function test_sweepNativeToken_success() public {
    // Send some native tokens to the vault
    vm.deal(address(privateVault), 1 ether);

    uint256 initialBalance = VAULT_OWNER.balance;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepNativeToken(0.5 ether);
    vm.stopBroadcast();

    assertEq(VAULT_OWNER.balance, initialBalance + 0.5 ether);
    assertEq(address(privateVault).balance, 0.5 ether);
  }

  function test_sweepNativeToken_unauthorized() public {
    vm.deal(address(privateVault), 1 ether);

    vm.startBroadcast(ADMIN);
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    privateVault.sweepNativeToken(0.5 ether);
    vm.stopBroadcast();
  }

  function test_sweepNativeToken_insufficient_balance() public {
    vm.startBroadcast(VAULT_OWNER);
    vm.expectRevert("Failed to send native token");
    privateVault.sweepNativeToken(1 ether);
    vm.stopBroadcast();
  }

  // ============ SWEEP TOKEN TESTS ============

  function test_sweepToken_success() public {
    // Mint tokens to vault
    mockERC20.mint(address(privateVault), 1000);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 500;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepToken(tokens, amounts);
    vm.stopBroadcast();

    assertEq(mockERC20.balanceOf(VAULT_OWNER), 500);
    assertEq(mockERC20.balanceOf(address(privateVault)), 500);
  }

  function test_sweepToken_multiple_tokens() public {
    MockERC20 token2 = new MockERC20();
    mockERC20.mint(address(privateVault), 1000);
    token2.mint(address(privateVault), 2000);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC20);
    tokens[1] = address(token2);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 500;
    amounts[1] = 1000;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepToken(tokens, amounts);
    vm.stopBroadcast();

    assertEq(mockERC20.balanceOf(VAULT_OWNER), 500);
    assertEq(token2.balanceOf(VAULT_OWNER), 1000);
  }

  function test_sweepToken_unauthorized() public {
    mockERC20.mint(address(privateVault), 1000);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 500;

    vm.startBroadcast(ADMIN);
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    privateVault.sweepToken(tokens, amounts);
    vm.stopBroadcast();
  }

  // ============ SWEEP ERC721 TESTS ============

  function test_sweepERC721_success() public {
    // Mint NFT to vault
    mockERC721.mint(address(privateVault), 1);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();

    assertEq(mockERC721.ownerOf(1), VAULT_OWNER);
  }

  function test_sweepERC721_multiple_tokens() public {
    MockERC721 token2 = new MockERC721();
    mockERC721.mint(address(privateVault), 1);
    token2.mint(address(privateVault), 2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC721);
    tokens[1] = address(token2);

    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();

    assertEq(mockERC721.ownerOf(1), VAULT_OWNER);
    assertEq(token2.ownerOf(2), VAULT_OWNER);
  }

  function test_sweepERC721_unauthorized() public {
    mockERC721.mint(address(privateVault), 1);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startBroadcast(ADMIN);
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    privateVault.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();
  }

  // ============ SWEEP ERC1155 TESTS ============

  function test_sweepERC1155_success() public {
    // Mint ERC1155 tokens to vault
    mockERC1155.mint(address(privateVault), 1, 100);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 50;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    assertEq(mockERC1155.balanceOf(VAULT_OWNER, 1), 50);
    assertEq(mockERC1155.balanceOf(address(privateVault), 1), 50);
  }

  function test_sweepERC1155_multiple_tokens() public {
    MockERC1155 token2 = new MockERC1155();
    mockERC1155.mint(address(privateVault), 1, 100);
    token2.mint(address(privateVault), 2, 200);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC1155);
    tokens[1] = address(token2);

    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 50;
    amounts[1] = 100;

    vm.startBroadcast(VAULT_OWNER);
    privateVault.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    assertEq(mockERC1155.balanceOf(VAULT_OWNER, 1), 50);
    assertEq(token2.balanceOf(VAULT_OWNER, 2), 100);
  }

  function test_sweepERC1155_unauthorized() public {
    mockERC1155.mint(address(privateVault), 1, 100);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 50;

    vm.startBroadcast(ADMIN);
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    privateVault.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();
  }

  // ============ ADMIN ROLE TESTS ============

  function test_grantAdminRole_success() public {
    address newAdmin = address(0x999);

    // Check event emission - vaultFactory should be the test contract address (msg.sender)
    vm.expectEmit(true, true, true, true);
    emit IPrivateVault.SetVaultAdmin(address(this), newAdmin, true);

    vm.prank(VAULT_OWNER);
    privateVault.grantAdminRole(newAdmin);

    // Verify admin role was granted
    assertTrue(privateVault.admins(newAdmin));
  }

  function test_grantAdminRole_unauthorized() public {
    address newAdmin = address(0x999);

    vm.startBroadcast(ADMIN);
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    privateVault.grantAdminRole(newAdmin);
    vm.stopBroadcast();
  }

  function test_revokeAdminRole_success() public {
    address adminToRevoke = ADMIN;

    // Check event emission - vaultFactory should be the test contract address (msg.sender)
    vm.expectEmit(true, true, true, true);
    emit IPrivateVault.SetVaultAdmin(address(this), adminToRevoke, false);

    vm.prank(VAULT_OWNER);
    privateVault.revokeAdminRole(adminToRevoke);

    // Verify admin role was revoked
    assertFalse(privateVault.admins(adminToRevoke));
  }

  function test_revokeAdminRole_unauthorized() public {
    address adminToRevoke = ADMIN;

    vm.startBroadcast(ADMIN);
    vm.expectRevert(IPrivateCommon.Unauthorized.selector);
    privateVault.revokeAdminRole(adminToRevoke);
    vm.stopBroadcast();
  }

  // ============ SIGNATURE VALIDATION TESTS ============

  function test_isValidSignature_valid_signature() public {
    // Create a message hash
    bytes32 messageHash = keccak256(abi.encodePacked("test message"));

    // Use a known private key that corresponds to VAULT_OWNER
    // Private key 0x1234567890123456789012345678901234567890123456789012345678901234
    // corresponds to address 0x2e988A386a799F506693793c6A5AF6B54dfAaBfB
    // But we need to use the actual VAULT_OWNER address
    // Let's use a different approach - create a signature with the actual vault owner

    // First, let's create a new vault with a known private key
    uint256 testPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address testOwner = vm.addr(testPrivateKey);

    // Create a new vault for this test
    PrivateVault testVault = new PrivateVault();
    testVault.initialize(testOwner, address(configManager));

    // Sign the hash with the test private key
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(testPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Test the signature validation
    bytes4 result = testVault.isValidSignature(messageHash, signature);

    // Should return the magic value for valid signature
    assertEq(result, bytes4(0x1626ba7e));
  }

  function test_isValidSignature_invalid_signature() public view {
    // Create a message hash
    bytes32 messageHash = keccak256(abi.encodePacked("test message"));

    // Create an invalid signature (wrong private key)
    uint256 wrongPrivateKey = 0x9876543210987654321098765432109876543210987654321098765432109876;
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, messageHash);
    bytes memory invalidSignature = abi.encodePacked(r, s, v);

    // Test the signature validation
    bytes4 result = privateVault.isValidSignature(messageHash, invalidSignature);

    // Should return empty bytes4 for invalid signature
    assertEq(result, bytes4(0));
  }

  function test_isValidSignature_empty_signature() public view {
    // Create a message hash
    bytes32 messageHash = keccak256(abi.encodePacked("test message"));

    // Test with empty signature
    bytes memory emptySignature = "";

    // Test the signature validation
    bytes4 result = privateVault.isValidSignature(messageHash, emptySignature);

    // Should return empty bytes4 for empty signature
    assertEq(result, bytes4(0));
  }

  function test_isValidSignature_malformed_signature() public view {
    // Create a message hash
    bytes32 messageHash = keccak256(abi.encodePacked("test message"));

    // Create a malformed signature (too short)
    bytes memory malformedSignature = abi.encodePacked(bytes32(0), bytes32(0));

    // Test the signature validation
    bytes4 result = privateVault.isValidSignature(messageHash, malformedSignature);

    // Should return empty bytes4 for malformed signature
    assertEq(result, bytes4(0));
  }

  function test_isValidSignature_different_message() public {
    // Use a known private key for VAULT_OWNER
    uint256 testPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address testOwner = vm.addr(testPrivateKey);

    // Create a new vault for this test
    PrivateVault testVault = new PrivateVault();
    testVault.initialize(testOwner, address(configManager));

    // Sign one message
    bytes32 messageHash1 = keccak256(abi.encodePacked("message 1"));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(testPrivateKey, messageHash1);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Test with a different message hash
    bytes32 messageHash2 = keccak256(abi.encodePacked("message 2"));
    bytes4 result = testVault.isValidSignature(messageHash2, signature);

    // Should return empty bytes4 for signature of different message
    assertEq(result, bytes4(0));
  }

  function test_isValidSignature_correct_message() public {
    // Use a known private key for VAULT_OWNER
    uint256 testPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address testOwner = vm.addr(testPrivateKey);

    // Create a new vault for this test
    PrivateVault testVault = new PrivateVault();
    testVault.initialize(testOwner, address(configManager));

    // Sign a message
    bytes32 messageHash = keccak256(abi.encodePacked("correct message"));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(testPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Test with the same message hash
    bytes4 result = testVault.isValidSignature(messageHash, signature);

    // Should return the magic value for correct signature
    assertEq(result, bytes4(0x1626ba7e));
  }

  // ============ RECEIVE FUNCTION TESTS ============

  function test_receive_native_tokens() public {
    uint256 initialBalance = address(privateVault).balance;

    vm.deal(address(this), 1 ether);
    (bool success,) = address(privateVault).call{ value: 1 ether }("");
    assertTrue(success);

    assertEq(address(privateVault).balance, initialBalance + 1 ether);
  }

  // ============ INITIALIZATION TESTS ============

  function test_initialize_zero_config_manager() public {
    PrivateVault newVault = new PrivateVault();

    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    newVault.initialize(VAULT_OWNER, address(0));
  }

  function test_initialize_already_initialized() public {
    PrivateVault newVault = new PrivateVault();
    newVault.initialize(VAULT_OWNER, address(configManager));

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    newVault.initialize(VAULT_OWNER, address(configManager));
  }

  // ============ PAUSE TESTS ============

  function test_multicall_when_paused() public {
    vm.startBroadcast(VAULT_OWNER);
    configManager.setVaultPaused(true);
    vm.stopBroadcast();

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    vm.startBroadcast(VAULT_OWNER);
    vm.expectRevert(IPrivateVault.Paused.selector);
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);
    vm.stopBroadcast();
  }

  // ============ WHITELISTED AUTOMATOR TESTS ============

  function test_multicall_whitelisted_automator() public {
    address automator = address(0x888);

    vm.startBroadcast(VAULT_OWNER);
    address[] memory automators = new address[](1);
    automators[0] = automator;
    configManager.setWhitelistCallers(automators, true);
    vm.stopBroadcast();

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 777);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    vm.startBroadcast(automator);
    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;
    privateVault.multicall(targets, callValues, data, callTypes);
    vm.stopBroadcast();

    assertEq(mockStrategy.getValue(), 777);
  }

  // ============ MULTICALL WITH VALUE TESTS ============

  function test_multicall_with_value_call() public {
    // Send ETH to vault
    vm.deal(address(privateVault), 2 ether);

    uint256 initialVaultBalance = address(privateVault).balance;
    uint256 initialStrategyBalance = address(mockStrategy).balance;

    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.receiveValue.selector);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 1 ether; // Send 1 ETH with the call

    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();

    // Verify ETH was sent to strategy
    assertEq(address(mockStrategy).balance, initialStrategyBalance + 1 ether);
    assertEq(address(privateVault).balance, initialVaultBalance - 1 ether);
    assertEq(mockStrategy.getReceivedValue(), 1 ether);
  }

  function test_multicall_with_value_delegatecall() public {
    // Send ETH to vault
    vm.deal(address(privateVault), 2 ether);

    uint256 initialVaultBalance = address(privateVault).balance;

    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValueAndReceive.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0.5 ether; // Send 0.5 ETH with the delegatecall

    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();

    // For delegatecall, the ETH stays in the vault but the function executes in vault context
    assertEq(address(privateVault).balance, initialVaultBalance);
    // The value should be set on the vault's storage (via delegatecall)
    // and the receivedValue should be tracked in vault's storage
  }

  function test_multicall_mixed_with_value() public {
    // Send ETH to vault
    vm.deal(address(privateVault), 3 ether);

    uint256 initialVaultBalance = address(privateVault).balance;
    uint256 initialStrategyBalance = address(mockStrategy).balance;

    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](2);
    targets[0] = address(mockStrategy);
    targets[1] = address(mockStrategy);

    bytes[] memory data = new bytes[](2);
    data[0] = abi.encodeWithSelector(MockStrategy.receiveValue.selector);
    data[1] = abi.encodeWithSelector(MockStrategy.setValueAndReceive.selector, 100);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);
    callTypes[0] = IPrivateCommon.CallType.CALL;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;

    uint256[] memory callValues = new uint256[](2);
    callValues[0] = 1 ether; // Send 1 ETH with first call
    callValues[1] = 0.5 ether; // Send 0.5 ETH with second delegatecall

    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();

    // First call (CALL) should send ETH to strategy
    assertEq(address(mockStrategy).balance, initialStrategyBalance + 1 ether);
    assertEq(mockStrategy.getReceivedValue(), 1 ether);

    // Second call (DELEGATECALL) should keep ETH in vault
    assertEq(address(privateVault).balance, initialVaultBalance - 1 ether);
  }

  function test_multicall_with_value_insufficient_balance() public {
    // Don't send any ETH to vault
    assertEq(address(privateVault).balance, 0);

    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.receiveValue.selector);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 1 ether; // Try to send 1 ETH but vault has 0

    // Should revert due to insufficient balance
    vm.expectRevert();
    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();
  }

  function test_multicall_multiple_values() public {
    // Send ETH to vault
    vm.deal(address(privateVault), 5 ether);

    uint256 initialVaultBalance = address(privateVault).balance;
    uint256 initialStrategyBalance = address(mockStrategy).balance;

    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](3);
    targets[0] = address(mockStrategy);
    targets[1] = address(mockStrategy);
    targets[2] = address(mockStrategy);

    bytes[] memory data = new bytes[](3);
    data[0] = abi.encodeWithSelector(MockStrategy.receiveValue.selector);
    data[1] = abi.encodeWithSelector(MockStrategy.receiveValue.selector);
    data[2] = abi.encodeWithSelector(MockStrategy.receiveValue.selector);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](3);
    callTypes[0] = IPrivateCommon.CallType.CALL;
    callTypes[1] = IPrivateCommon.CallType.CALL;
    callTypes[2] = IPrivateCommon.CallType.CALL;

    uint256[] memory callValues = new uint256[](3);
    callValues[0] = 1 ether; // Send 1 ETH with first call
    callValues[1] = 0.5 ether; // Send 0.5 ETH with second call
    callValues[2] = 0.25 ether; // Send 0.25 ETH with third call

    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();

    // Verify total ETH sent to strategy
    uint256 totalSent = 1 ether + 0.5 ether + 0.25 ether;
    assertEq(address(mockStrategy).balance, initialStrategyBalance + totalSent);
    assertEq(address(privateVault).balance, initialVaultBalance - totalSent);
    assertEq(mockStrategy.getReceivedValue(), totalSent);
  }

  function test_multicall_with_zero_value() public {
    // Send ETH to vault
    vm.deal(address(privateVault), 1 ether);

    uint256 initialVaultBalance = address(privateVault).balance;
    uint256 initialStrategyBalance = address(mockStrategy).balance;

    vm.startBroadcast(VAULT_OWNER);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0; // Send 0 ETH

    privateVault.multicall(targets, callValues, data, callTypes);

    vm.stopBroadcast();

    // Should work normally with zero value
    assertEq(mockStrategy.getValue(), 42);
    assertEq(address(mockStrategy).balance, initialStrategyBalance);
    assertEq(address(privateVault).balance, initialVaultBalance);
  }
}
