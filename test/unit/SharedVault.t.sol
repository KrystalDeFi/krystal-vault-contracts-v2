// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// Mock ERC20 token for testing
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

// Mock strategy that validates tokens and sets a value
contract MockSharedStrategy is ISharedStrategy {
  uint256 public lastValue;

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    uint256 value = abi.decode(data, (uint256));
    lastValue = value;
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }
}

// Mock strategy that fails
contract MockFailingStrategy is ISharedStrategy {
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    revert("Strategy failed");
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }
}

// Mock swap target
contract MockSwapTarget {
  function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
    // Take tokenIn, give tokenOut
    MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    // Give 1:1 swap
    MockERC20(tokenOut).transfer(msg.sender, amountIn);
  }
}

// Mock ERC721 for sweep tests
contract MockERC721 {
  mapping(uint256 => address) public ownerOf;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    ownerOf[tokenId] = to;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
    require(ownerOf[tokenId] == from, "Not owner");
    ownerOf[tokenId] = to;
  }
}

// Mock ERC1155 for sweep tests
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 id, uint256 amount) external {
    balanceOf[to][id] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
    require(balanceOf[from][id] >= amount, "Insufficient balance");
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;
  }
}

contract SharedVaultTest is TestCommon {
  SharedVault public vault;
  SharedConfigManager public configManager;

  MockERC20 public tokenA;
  MockERC20 public tokenB;
  MockERC20 public tokenC;
  MockERC20 public tokenD;
  MockERC20 public tokenE; // non-vault token

  MockSharedStrategy public mockStrategy;
  MockFailingStrategy public failingStrategy;
  MockSwapTarget public swapTarget;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;

  address public constant VAULT_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant ADMIN = 0x1234567890123456789012345678901234567891;
  address public constant OPERATOR = 0x1234567890123456789012345678901234567892;
  address public constant DEPOSITOR = 0x1234567890123456789012345678901234567893;
  address public constant NON_AUTHORIZED = 0x1234567890123456789012345678901234567894;

  function setUp() public {
    // Deploy mock tokens
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");
    tokenC = new MockERC20("Token C", "TKC");
    tokenD = new MockERC20("Token D", "TKD");
    tokenE = new MockERC20("Token E", "TKE");

    // Deploy mock contracts
    mockStrategy = new MockSharedStrategy();
    failingStrategy = new MockFailingStrategy();
    swapTarget = new MockSwapTarget();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();

    // Deploy config manager
    configManager = new SharedConfigManager();
    address[] memory targets = new address[](2);
    targets[0] = address(swapTarget);
    targets[1] = address(mockStrategy);
    address[] memory callers = new address[](0);
    configManager.initialize(address(this), targets, callers, address(this));

    // Deploy vault
    vault = new SharedVault();

    // Mint initial tokens and transfer to vault for initialization
    tokenA.mint(address(this), 1000e18);
    tokenB.mint(address(this), 2000e18);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Transfer initial tokens to vault (factory would do this)
    tokenA.transfer(address(vault), 100e18);
    tokenB.transfer(address(vault), 200e18);

    // Initialize
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initialAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vault.initialize("Shared Vault", vaultTokens, initialAmounts, VAULT_OWNER, address(configManager));

    // Setup roles
    vm.startPrank(VAULT_OWNER);
    vault.grantAdminRole(ADMIN);
    vault.setOperator(OPERATOR);
    vm.stopPrank();
  }

  // ==================== Initialization Tests ====================

  function test_initialize_success() public view {
    assertEq(vault.vaultOwner(), VAULT_OWNER);
    assertEq(vault.tokenCount(), 4);
    assertEq(vault.decimals(), 18);
    assertTrue(vault.isVaultToken(address(tokenA)));
    assertTrue(vault.isVaultToken(address(tokenB)));
    assertTrue(vault.isVaultToken(address(tokenC)));
    assertTrue(vault.isVaultToken(address(tokenD)));
    assertFalse(vault.isVaultToken(address(tokenE)));

    // Initial shares minted to owner
    uint256 expectedShares = 100e18 * vault.SHARES_PRECISION();
    assertEq(vault.balanceOf(VAULT_OWNER), expectedShares);
    assertGt(vault.totalSupply(), 0);
  }

  function test_initialize_fail_duplicate_token() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenA), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.DuplicateToken.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(configManager));
  }

  function test_initialize_fail_too_few_tokens() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(0), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.NoTokensConfigured.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(configManager));
  }

  // ==================== Deposit Tests ====================

  function test_deposit_first() public {
    // Create a fresh vault with no initial deposit
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(configManager));

    // First deposit
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault2), type(uint256).max);
    tokenB.approve(address(vault2), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault2.deposit(depositAmounts, 0);

    assertEq(shares, 50e18 * vault2.SHARES_PRECISION());
    assertEq(vault2.balanceOf(DEPOSITOR), shares);
    assertEq(tokenA.balanceOf(address(vault2)), 50e18);
    assertEq(tokenB.balanceOf(address(vault2)), 100e18);
    vm.stopPrank();
  }

  function test_deposit_subsequent_proportional() public {
    // Deposit proportionally
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Current ratio is 100:200 = 1:2, deposit 50:100 maintains ratio
    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);

    assertGt(shares, 0);
    assertEq(vault.balanceOf(DEPOSITOR), shares);
    vm.stopPrank();
  }

  function test_deposit_excess_capped_at_proportional() public {
    // Vault is 1:2 (100A:200B). User provides 50A + 50B — more A than needed.
    // The minimum-ratio token is B (50/200 < 50/100), so shares are computed from B.
    // The vault takes only the proportional A amount and leaves excess A with the user.
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256 aBalanceBefore = tokenA.balanceOf(DEPOSITOR);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(50e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);

    assertGt(shares, 0);
    // Only proportional A was taken: 50B / 200B * 100A = 25A
    assertEq(tokenA.balanceOf(DEPOSITOR), aBalanceBefore - 25e18);
    assertEq(tokenB.balanceOf(DEPOSITOR), 0);
    vm.stopPrank();
  }

  function test_deposit_fail_insufficient_token_b() public {
    // User provides correct A but less B than the ratio requires
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Vault is 1:2. Depositing 50A + 50B: min shares come from B (25% of pool),
    // but expectedA for those shares = 25e18. 50A >= 25A so it passes.
    // Now try providing only 1B — min shares from B = 1/200 * totalSupply,
    // expectedA = (1/200 * totalSupply) * 100 / totalSupply = 0.5 → 0 (rounds down).
    // That would succeed, so test a case that truly fails: amounts[i] < expectedAmount.
    // Force fail: provide 0B when B balance is 200e18 (required).
    uint256[4] memory depositAmounts = [uint256(50e18), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    vault.deposit(depositAmounts, 0);
    vm.stopPrank();
  }

  function test_deposit_shares_independent_of_reference_token() public {
    // Regression: the minimum-ratio approach must yield the same shares regardless of which
    // token the caller leads with. Vault is 100A:200B (1:2). Exact proportional 10A:20B.
    tokenA.mint(DEPOSITOR, 10e18);
    tokenB.mint(DEPOSITOR, 20e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256 supplyBefore = vault.totalSupply();
    uint256[4] memory depositAmounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);
    vm.stopPrank();

    // 10A / 100A == 20B / 200B == 10% of pool → shares = 10% of prior supply
    assertEq(shares, supplyBefore / 10);
    assertEq(tokenA.balanceOf(address(vault)), 110e18);
    assertEq(tokenB.balanceOf(address(vault)), 220e18);
  }

  function test_deposit_fail_insufficient_shares() public {
    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 2e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(1e18), uint256(2e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InsufficientShares.selector);
    vault.deposit(depositAmounts, type(uint256).max);
    vm.stopPrank();
  }

  // ==================== Withdraw Tests ====================

  function test_withdraw_proportional() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;

    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(halfShares, minAmounts);
    vm.stopPrank();

    // Should get ~50% of each token
    assertEq(amounts[0], 50e18);
    assertEq(amounts[1], 100e18);
    assertEq(vault.balanceOf(VAULT_OWNER), ownerShares - halfShares);
  }

  function test_withdraw_all() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(ownerShares, minAmounts);
    vm.stopPrank();

    assertEq(amounts[0], 100e18);
    assertEq(amounts[1], 200e18);
    assertEq(vault.balanceOf(VAULT_OWNER), 0);
    assertEq(vault.totalSupply(), 0);
  }

  function test_withdraw_fail_insufficient_shares() public {
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.InsufficientShares.selector);
    vault.withdraw(1, minAmounts);
    vm.stopPrank();
  }

  function test_withdraw_fail_min_amounts() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.withdraw(ownerShares, minAmounts);
    vm.stopPrank();
  }

  // ==================== Execute Tests ====================

  function test_execute_success() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory data = abi.encode(uint256(42));
    vault.execute(address(mockStrategy), data);
    vm.stopPrank();
  }

  function test_execute_admin() public {
    vm.startPrank(ADMIN);
    bytes memory data = abi.encode(uint256(42));
    vault.execute(address(mockStrategy), data);
    vm.stopPrank();
  }

  function test_execute_fail_unauthorized() public {
    vm.startPrank(NON_AUTHORIZED);
    bytes memory data = abi.encode(uint256(42));
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(address(mockStrategy), data);
    vm.stopPrank();
  }

  function test_execute_fail_non_whitelisted_strategy() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory data = abi.encode(uint256(42));
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidStrategy.selector, address(failingStrategy)));
    vault.execute(address(failingStrategy), data);
    vm.stopPrank();
  }

  // ==================== Swap Tests ====================

  function test_swap_success() public {
    // Give swap target some tokenB to return
    tokenB.mint(address(swapTarget), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory swapData = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 10e18));

    uint256 balanceBefore = tokenB.balanceOf(address(vault));
    vault.swap(address(swapTarget), address(tokenA), address(tokenB), 10e18, 9e18, swapData);
    uint256 balanceAfter = tokenB.balanceOf(address(vault));

    assertEq(balanceAfter - balanceBefore, 10e18);
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_in() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapData = abi.encodeCall(MockSwapTarget.swap, (address(tokenE), address(tokenA), 10e18));
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.swap(address(swapTarget), address(tokenE), address(tokenA), 10e18, 0, swapData);
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_out() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapData = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenE), 10e18));
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.swap(address(swapTarget), address(tokenA), address(tokenE), 10e18, 0, swapData);
    vm.stopPrank();
  }

  function test_swap_fail_non_whitelisted_target() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapData = "";
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, NON_AUTHORIZED));
    vault.swap(NON_AUTHORIZED, address(tokenA), address(tokenB), 10e18, 0, swapData);
    vm.stopPrank();
  }

  // ==================== Sweep Tests (Operator) ====================

  function test_sweep_non_vault_token() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(OPERATOR);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();

    assertEq(tokenE.balanceOf(OPERATOR), 100e18);
    assertEq(tokenE.balanceOf(address(vault)), 0);
  }

  function test_sweep_fail_vault_token() public {
    vm.startPrank(OPERATOR);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenA);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 1e18;
    vm.expectRevert(ISharedCommon.CannotSweepVaultToken.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();
  }

  function test_sweep_fail_non_operator() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(VAULT_OWNER);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, VAULT_OWNER);
    vm.stopPrank();
  }

  function test_sweep_native_token() public {
    vm.deal(address(vault), 1 ether);

    vm.startPrank(OPERATOR);
    vault.sweepNativeToken(1 ether, OPERATOR);
    vm.stopPrank();

    assertEq(OPERATOR.balance, 1 ether);
  }

  function test_sweep_erc721() public {
    mockERC721.mint(address(vault), 1);

    vm.startPrank(OPERATOR);
    vault.sweepERC721(address(mockERC721), 1, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC721.ownerOf(1), OPERATOR);
  }

  function test_sweep_erc1155() public {
    mockERC1155.mint(address(vault), 1, 100);

    vm.startPrank(OPERATOR);
    vault.sweepERC1155(address(mockERC1155), 1, 50, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC1155.balanceOf(OPERATOR, 1), 50);
    assertEq(mockERC1155.balanceOf(address(vault), 1), 50);
  }

  // ==================== Role Tests ====================

  function test_grant_revoke_admin() public {
    address newAdmin = address(0x999);
    vm.startPrank(VAULT_OWNER);
    vault.grantAdminRole(newAdmin);
    vm.stopPrank();

    // New admin can execute
    vm.startPrank(newAdmin);
    bytes memory data = abi.encode(uint256(42));
    vault.execute(address(mockStrategy), data);
    vm.stopPrank();

    // Revoke
    vm.startPrank(VAULT_OWNER);
    vault.revokeAdminRole(newAdmin);
    vm.stopPrank();

    vm.startPrank(newAdmin);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(address(mockStrategy), data);
    vm.stopPrank();
  }

  function test_set_operator() public {
    address newOp = address(0x888);
    vm.startPrank(VAULT_OWNER);
    vault.setOperator(newOp);
    vm.stopPrank();

    assertEq(vault.operator(), newOp);
  }

  function test_set_operator_fail_zero_address() public {
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    vault.setOperator(address(0));
    vm.stopPrank();
  }

  function test_transfer_ownership() public {
    address newOwner = address(0x777);
    vm.startPrank(VAULT_OWNER);
    vault.transferOwnership(newOwner);
    vm.stopPrank();

    assertEq(vault.vaultOwner(), newOwner);

    // Old owner can't act
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.grantAdminRole(address(0x666));
    vm.stopPrank();
  }

  // ==================== Pause Tests ====================

  function test_global_pause_blocks_deposit() public {
    configManager.setVaultPaused(true);

    tokenA.mint(DEPOSITOR, 10e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.deposit(amounts, 0);
    vm.stopPrank();
  }

  function test_global_pause_blocks_execute() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(address(mockStrategy), abi.encode(uint256(1)));
    vm.stopPrank();
  }

  function test_global_pause_blocks_swap() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.swap(address(swapTarget), address(tokenA), address(tokenB), 1e18, 0, "");
    vm.stopPrank();
  }

  function test_per_vault_pause_blocks_deposit() public {
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.stopPrank();

    tokenA.mint(DEPOSITOR, 10e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.deposit(amounts, 0);
    vm.stopPrank();
  }

  function test_per_vault_pause_blocks_execute() public {
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(address(mockStrategy), abi.encode(uint256(1)));
    vm.stopPrank();
  }

  function test_per_vault_pause_unpause() public {
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    assertTrue(vault.paused());

    // Unpaused
    vault.setPaused(false);
    assertFalse(vault.paused());

    // Can execute again
    bytes memory data = abi.encode(uint256(42));
    vault.execute(address(mockStrategy), data);
    vm.stopPrank();
  }

  function test_per_vault_pause_independent_of_global() public {
    // Per-vault paused, global not paused
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(address(mockStrategy), abi.encode(uint256(1)));
    vm.stopPrank();

    // Per-vault unpaused, global paused
    vm.prank(VAULT_OWNER);
    vault.setPaused(false);
    configManager.setVaultPaused(true);
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(address(mockStrategy), abi.encode(uint256(1)));
    vm.stopPrank();
  }

  // ==================== Preview Tests ====================

  function test_preview_deposit() public view {
    uint256[4] memory amounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 previewShares = vault.previewDeposit(amounts);
    assertGt(previewShares, 0);
  }

  function test_preview_withdraw() public view {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory previewAmounts = vault.previewWithdraw(ownerShares);
    assertEq(previewAmounts[0], 100e18);
    assertEq(previewAmounts[1], 200e18);
  }

  // ==================== View Tests ====================

  function test_get_tokens() public view {
    address[4] memory vaultTokens = vault.getTokens();
    assertEq(vaultTokens[0], address(tokenA));
    assertEq(vaultTokens[1], address(tokenB));
    assertEq(vaultTokens[2], address(tokenC));
    assertEq(vaultTokens[3], address(tokenD));
  }

  function test_get_idle_balances() public view {
    uint256[4] memory balances = vault.getIdleBalances();
    assertEq(balances[0], 100e18);
    assertEq(balances[1], 200e18);
    assertEq(balances[2], 0);
    assertEq(balances[3], 0);
  }
}
