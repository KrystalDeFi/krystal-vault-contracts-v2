// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { Vm } from "forge-std/Vm.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock WETH9 for testing native ETH wrapping/unwrapping
contract MockWETH9 {
  string public name = "Wrapped Ether";
  string public symbol = "WETH";
  uint8 public decimals = 18;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  receive() external payable {
    deposit();
  }

  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
  }

  function withdraw(uint256 wad) external {
    require(balanceOf[msg.sender] >= wad, "Insufficient WETH");
    balanceOf[msg.sender] -= wad;
    (bool ok, ) = msg.sender.call{ value: wad }("");
    require(ok, "ETH transfer failed");
  }

  function totalSupply() external view returns (uint256) {
    return address(this).balance;
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

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256) external override {}
}

// Mock strategy whose exitProportional always reverts (simulates a buggy deployed strategy)
contract MockBrokenExitStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) = abi.decode(
      data,
      (address, uint256, address, address)
    );
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory) {
    revert("broken exit");
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256) external override {}
}

// Mock strategy whose depositProportional always reverts but getPositionAmounts returns non-zero.
// Simulates a rugged pool where the NFPM rejects increaseLiquidity but the strategy still reports liquidity.
contract MockBrokenDepositStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) = abi.decode(
      data,
      (address, uint256, address, address)
    );
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (100e18, 100e18);
  }

  function depositProportional(address, uint256, uint256, uint256) external pure override {
    revert("pool rugged");
  }
}

// Mock strategy that fails
contract MockFailingStrategy is ISharedStrategy {
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    revert("Strategy failed");
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256) external override {}
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

/// @dev Simulates an external contract called via CALL_WITH_POSITIONS that returns PositionChange[].
///      Unlike strategies (which run via delegatecall), this is a standalone contract that the
///      vault calls directly. It mints/burns token approvals and returns position tracking info.
contract MockDirectPositionCreator is ISharedStrategy {
  /// @dev Creates a position: accepts tokens, records LP, returns PositionChange with isAdd=true.
  function createPosition(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1
  ) external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  /// @dev Removes a position: returns PositionChange with isAdd=false.
  function removePosition(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1
  ) external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: false, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  /// @dev Returns an empty PositionChange[] — simulates a no-op call.
  function noChanges() external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  /// @dev Reverts — simulates a failing target call.
  function alwaysFail() external pure returns (PositionChange[] memory) {
    revert("DirectCreator: always fails");
  }

  // ISharedStrategy stubs (not used in CALL_WITH_POSITIONS path)
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256) external override {}
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

// Mock LP pool that holds tokens and simulates proportional LP exits
contract MockLPPool {
  struct LP {
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
  }

  mapping(bytes32 => LP) public lps;

  function deposit(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    uint256 _amount0,
    uint256 _amount1
  ) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    lp.token0 = token0;
    lp.token1 = token1;
    lp.amount0 += _amount0;
    lp.amount1 += _amount1;
  }

  function exit(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, address recipient) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    uint256 exit0 = (lp.amount0 * shares) / totalShares;
    uint256 exit1 = (lp.amount1 * shares) / totalShares;
    if (exit0 > 0) {
      MockERC20(lp.token0).transfer(recipient, exit0);
      lp.amount0 -= exit0;
    }
    if (exit1 > 0) {
      MockERC20(lp.token1).transfer(recipient, exit1);
      lp.amount1 -= exit1;
    }
  }

  function getAmounts(address nfpm, uint256 tokenId) external view returns (uint256, uint256) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (lps[key].amount0, lps[key].amount1);
  }
}

// Mock strategy that simulates realistic LP creation + proportional exits
// Uses immutable lpPool ref so it's accessible in delegatecall context
contract MockLPExitStrategy is ISharedStrategy {
  address public immutable lpPool;

  /// @dev Emitted on proportional exit; under delegatecall this logs from the vault address.
  event ExitVaultOwnerFeeBps(uint16 basisPoints);

  constructor(address _lpPool) {
    lpPool = _lpPool;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1) = abi.decode(
      data,
      (address, uint256, address, address, uint256, uint256)
    );

    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);

    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);

    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16 vaultOwnerFeeBasisPoint
  ) external override returns (PositionChange[] memory changes) {
    emit ExitVaultOwnerFeeBps(vaultOwnerFeeBasisPoint);
    MockLPPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(
    address nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1) external override {
    if (amount0 == 0 && amount1 == 0) return;
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address token0, address token1, , ) = MockLPPool(lpPool).lps(key);
    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);
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
  MockDirectPositionCreator public directCreator;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;
  MockWETH9 public mockWeth;

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
    directCreator = new MockDirectPositionCreator();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();
    mockWeth = new MockWETH9();

    // Deploy config manager
    configManager = new SharedConfigManager();
    address[] memory targets = new address[](3);
    targets[0] = address(swapTarget);
    targets[1] = address(mockStrategy);
    targets[2] = address(directCreator);
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

    // Initialize: vaultFactory is msg.sender; operator matches factory.owner() (SharedVaultFactory passes owner()).
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initialAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    vault.initialize(
      "Shared Vault",
      vaultTokens,
      initialAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(0)
    );

    // Setup roles
    vault.grantAdminRole(ADMIN);
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

    // Initial shares minted to owner: always INITIAL_SHARES on first deposit
    assertEq(vault.balanceOf(VAULT_OWNER), vault.INITIAL_SHARES());
    assertGt(vault.totalSupply(), 0);
  }

  function test_initialize_fail_duplicate_token() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenA), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.DuplicateToken.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0));
  }

  function test_initialize_fail_too_few_tokens() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(0), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.NoTokensConfigured.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0));
  }

  // ==================== Deposit Tests ====================

  function test_deposit_first() public {
    // Create a fresh vault with no initial deposit
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0));
    vm.stopPrank();

    // First deposit
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault2), type(uint256).max);
    tokenB.approve(address(vault2), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault2.deposit(depositAmounts, 0);

    assertEq(shares, vault2.INITIAL_SHARES());
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
    uint256[4] memory amounts = vault.withdraw(halfShares, minAmounts, false);
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
    uint256[4] memory amounts = vault.withdraw(ownerShares, minAmounts, false);
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
    vault.withdraw(1, minAmounts, false);
    vm.stopPrank();
  }

  function test_withdraw_fail_min_amounts() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.withdraw(ownerShares, minAmounts, false);
    vm.stopPrank();
  }

  // ==================== Execute Tests ====================

  function test_execute_success() public {
    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_execute_admin() public {
    vm.startPrank(ADMIN);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_execute_fail_unauthorized() public {
    vm.startPrank(NON_AUTHORIZED);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_execute_fail_non_whitelisted_strategy() public {
    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(failingStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  // ==================== Swap-via-Execute Tests ====================

  function test_swap_success() public {
    // Give swap target some tokenB to return
    tokenB.mint(address(swapTarget), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 9e18, swapCalldata);

    uint256 balanceBefore = tokenB.balanceOf(address(vault));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    uint256 balanceAfter = tokenB.balanceOf(address(vault));

    assertEq(balanceAfter - balanceBefore, 10e18);
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_in() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenE), address(tokenA), 10e18));
    bytes memory actionData = abi.encode(address(tokenE), address(tokenA), 10e18, 0, swapCalldata);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_out() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenE), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenE), 10e18, 0, swapCalldata);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_swap_fail_non_whitelisted_target() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 0, "");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(NON_AUTHORIZED, actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, NON_AUTHORIZED));
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  // ==================== Sweep Tests (factory owner is vault operator) ====================

  function test_sweep_non_vault_token() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(VAULT_OWNER);
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
    vm.startPrank(VAULT_OWNER);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenA);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 1e18;
    vm.expectRevert(ISharedCommon.CannotSweepVaultToken.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, VAULT_OWNER);
    vm.stopPrank();
  }

  function test_sweep_fail_non_operator() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(OPERATOR);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();
  }

  function test_sweep_native_token() public {
    vm.deal(address(vault), 1 ether);

    vm.startPrank(VAULT_OWNER);
    vault.sweepNativeToken(1 ether, OPERATOR);
    vm.stopPrank();

    assertEq(OPERATOR.balance, 1 ether);
  }

  function test_sweep_erc721() public {
    mockERC721.mint(address(vault), 1);

    vm.startPrank(VAULT_OWNER);
    vault.sweepERC721(address(mockERC721), 1, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC721.ownerOf(1), OPERATOR);
  }

  function test_sweep_erc1155() public {
    mockERC1155.mint(address(vault), 1, 100);

    vm.startPrank(VAULT_OWNER);
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
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    // Revoke
    vm.startPrank(VAULT_OWNER);
    vault.revokeAdminRole(newAdmin);
    vm.stopPrank();

    vm.startPrank(newAdmin);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
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

  // ==================== Position Strategy Update via execute() Tests ====================

  function _setupVaultWithBrokenStrategy()
    internal
    returns (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId)
  {
    brokenStrat = new MockBrokenExitStrategy();
    fakeNfpm = makeAddr("nfpmMigrate");
    tokenId = 99;

    address[] memory newTargets = new address[](1);
    newTargets[0] = address(brokenStrat);
    configManager.setWhitelistTargets(newTargets, true);

    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    bytes memory stratData = abi.encode(fakeNfpm, tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
  }

  function _makeUpdate(
    address nfpm,
    uint256 tokenId,
    address strategy
  ) internal pure returns (ISharedVault.PositionStrategyUpdate[] memory updates) {
    updates = new ISharedVault.PositionStrategyUpdate[](1);
    updates[0] = ISharedVault.PositionStrategyUpdate(nfpm, tokenId, strategy);
  }

  function test_execute_strategy_update_happy_path() public {
    (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    (address storedBefore, , , , ) = vault.getPosition(0);
    assertEq(storedBefore, address(brokenStrat));

    MockLPPool lpPool = new MockLPPool();
    MockLPExitStrategy goodStrat = new MockLPExitStrategy(address(lpPool));
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(goodStrat);
    configManager.setWhitelistTargets(newTargets, true);

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionStrategyMigrated(
      VAULT_OWNER,
      fakeNfpm,
      tokenId,
      address(brokenStrat),
      address(goodStrat)
    );

    vm.prank(VAULT_OWNER);
    vault.execute(new ISharedVault.Action[](0), _makeUpdate(fakeNfpm, tokenId, address(goodStrat)));

    (address storedAfter, , , , ) = vault.getPosition(0);
    assertEq(storedAfter, address(goodStrat));
  }

  function test_execute_strategy_update_fail_unauthorized() public {
    (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();
    MockLPPool lpPool = new MockLPPool();
    MockLPExitStrategy goodStrat = new MockLPExitStrategy(address(lpPool));
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(goodStrat);
    configManager.setWhitelistTargets(newTargets, true);

    vm.prank(NON_AUTHORIZED);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(new ISharedVault.Action[](0), _makeUpdate(fakeNfpm, tokenId, address(goodStrat)));
    (brokenStrat);
  }

  function test_execute_strategy_update_fail_not_whitelisted() public {
    (, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();
    address notWhitelisted = makeAddr("notWhitelisted");

    vm.prank(VAULT_OWNER);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, notWhitelisted));
    vault.execute(new ISharedVault.Action[](0), _makeUpdate(fakeNfpm, tokenId, notWhitelisted));
  }

  function test_execute_strategy_update_fail_position_not_tracked() public {
    address fakeNfpm = makeAddr("nfpmNotTracked");
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(mockStrategy);
    configManager.setWhitelistTargets(newTargets, true);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.execute(new ISharedVault.Action[](0), _makeUpdate(fakeNfpm, 123, address(mockStrategy)));
  }

  function test_execute_strategy_update_unblocks_withdrawal() public {
    (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    // Withdrawal reverts while broken strategy is stored
    uint256 shares = vault.balanceOf(DEPOSITOR);
    vm.prank(DEPOSITOR);
    vm.expectRevert();
    vault.withdraw(shares, [uint256(0), uint256(0), uint256(0), uint256(0)], false);

    // Migrate via execute() strategyUpdates — no separate owner function needed
    MockLPPool lpPool = new MockLPPool();
    MockLPExitStrategy goodStrat = new MockLPExitStrategy(address(lpPool));
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(goodStrat);
    configManager.setWhitelistTargets(newTargets, true);

    vm.prank(VAULT_OWNER);
    vault.execute(new ISharedVault.Action[](0), _makeUpdate(fakeNfpm, tokenId, address(goodStrat)));

    // Now withdrawal succeeds
    vm.prank(DEPOSITOR);
    vault.withdraw(shares, [uint256(0), uint256(0), uint256(0), uint256(0)], false);
    (brokenStrat);
  }

  /// @notice _addPosition auto-updates pos.strategy when a strategy returns isAdd=true for an already-tracked position.
  function test_execute_via_new_strategy_auto_updates_position_strategy() public {
    (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    (address storedBefore, , , , ) = vault.getPosition(0);
    assertEq(storedBefore, address(brokenStrat));

    // Deploy a good replacement and whitelist it
    MockLPPool lpPool = new MockLPPool();
    MockLPExitStrategy goodStrat = new MockLPExitStrategy(address(lpPool));
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(goodStrat);
    configManager.setWhitelistTargets(newTargets, true);

    // Execute an action via goodStrat that returns isAdd=true for the same (nfpm, tokenId)
    // MockLPExitStrategy.execute decodes (nfpm, tokenId, token0, token1, amount0, amount1)
    bytes memory stratData = abi.encode(fakeNfpm, tokenId, address(tokenA), address(tokenB), uint256(0), uint256(0));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(goodStrat), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionStrategyMigrated(
      VAULT_OWNER,
      fakeNfpm,
      tokenId,
      address(brokenStrat),
      address(goodStrat)
    );
    vm.prank(VAULT_OWNER);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));

    (address storedAfter, , , , ) = vault.getPosition(0);
    assertEq(storedAfter, address(goodStrat));

    // Withdrawal now works because pos.strategy points to goodStrat
    uint256 shares = vault.balanceOf(DEPOSITOR);
    vm.prank(DEPOSITOR);
    vault.withdraw(shares, [uint256(0), uint256(0), uint256(0), uint256(0)], false);
  }

  // ==================== dropPosition Tests ====================

  function test_dropPosition_happy_path() public {
    (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    assertEq(vault.getPositionCount(), 1);

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionDropped(VAULT_OWNER, fakeNfpm, tokenId);
    vm.prank(VAULT_OWNER);
    vault.dropPosition(fakeNfpm, tokenId);

    assertEq(vault.getPositionCount(), 0);
    (brokenStrat);
  }

  function test_dropPosition_unblocks_deposit() public {
    // Deploy a strategy whose getPositionAmounts returns non-zero but depositProportional always reverts.
    // This simulates a rugged pool where the NFPM rejects increaseLiquidity calls.
    MockBrokenDepositStrategy brokenDepStrat = new MockBrokenDepositStrategy();
    address[] memory targets = new address[](1);
    targets[0] = address(brokenDepStrat);
    configManager.setWhitelistTargets(targets, true);

    // Initial deposit so we have a non-zero totalSupply to work against
    tokenA.mint(DEPOSITOR, 300e18);
    tokenB.mint(DEPOSITOR, 300e18);
    vm.prank(DEPOSITOR);
    tokenA.approve(address(vault), 300e18);
    vm.prank(DEPOSITOR);
    tokenB.approve(address(vault), 300e18);
    vm.prank(DEPOSITOR);
    vault.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);

    // Add the broken position via execute
    address fakeNfpm = address(0xBEEF1);
    uint256 tokenId = 42;
    bytes memory stratData = abi.encode(fakeNfpm, tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenDepStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    assertEq(vault.getPositionCount(), 1);

    // Second deposit fails — getPositionAmounts returns non-zero so toAdd > 0, then depositProportional reverts.
    // The inner revert string propagates through the delegatecall bubble-up path.
    vm.prank(DEPOSITOR);
    vm.expectRevert("pool rugged");
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);

    // Drop the broken position — deposit must succeed afterwards
    vm.prank(VAULT_OWNER);
    vault.dropPosition(fakeNfpm, tokenId);
    assertEq(vault.getPositionCount(), 0);

    vm.prank(DEPOSITOR);
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
  }

  function test_dropPosition_fail_not_tracked() public {
    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.dropPosition(address(0xDEAD), 999);
  }

  function test_dropPosition_fail_unauthorized() public {
    (MockBrokenExitStrategy brokenStrat, address fakeNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.dropPosition(fakeNfpm, tokenId);
    (brokenStrat);
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
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_global_pause_blocks_swap() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 1e18, 0, "");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
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
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_per_vault_pause_unpause() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    assertTrue(vault.paused());

    // Unpaused
    vault.setPaused(false);
    assertFalse(vault.paused());

    // Can execute again
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  function test_per_vault_pause_independent_of_global() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );

    // Per-vault paused, global not paused
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    // Per-vault unpaused, global paused
    vm.prank(VAULT_OWNER);
    vault.setPaused(false);
    configManager.setVaultPaused(true);
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  // ==================== Vault owner fee + platform fee (LpFeeTaker / config) ====================

  function test_set_platform_fee_basis_point() public {
    // Config manager owner is `address(this)` from setUp `initialize`
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(50);
    assertEq(configManager.platformFeeBasisPoint(), 50);
  }

  function test_set_platform_fee_basis_point_reverts_invalid() public {
    vm.startPrank(address(this));
    vm.expectRevert(ISharedCommon.InvalidFeeBasisPoint.selector);
    configManager.setPlatformFeeBasisPoint(10_001);
    vm.stopPrank();
  }

  function test_set_vault_owner_fee_basis_point() public {
    vm.prank(VAULT_OWNER);
    vault.setVaultOwnerFeeBasisPoint(250);
    assertEq(vault.vaultOwnerFeeBasisPoint(), 250);
  }

  function test_set_vault_owner_fee_basis_point_max() public {
    vm.prank(VAULT_OWNER);
    vault.setVaultOwnerFeeBasisPoint(10_000);
    assertEq(vault.vaultOwnerFeeBasisPoint(), 10_000);
  }

  function test_set_vault_owner_fee_basis_point_reverts_invalid() public {
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidVaultOwnerFeeBasisPoint.selector);
    vault.setVaultOwnerFeeBasisPoint(10_001);
    vm.stopPrank();
  }

  function test_set_vault_owner_fee_basis_point_unauthorized() public {
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.setVaultOwnerFeeBasisPoint(100);
  }

  /// @notice Withdraw delegatecalls `exitProportional` with the stored owner fee bps so strategies can apply performance fees.
  function test_withdraw_forwards_vault_owner_fee_bps_to_strategy() public {
    MockLPPool lpPoolContract = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(lpPoolContract));
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(lpStrategy);
    cm.initialize(VAULT_OWNER, targets, new address[](0), address(this));

    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    uint256 dep = 100e18;
    tA.mint(address(this), dep);
    tB.mint(address(this), dep);
    tA.transfer(address(v), dep);
    tB.transfer(address(v), dep);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [dep, dep, uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("FeeBpsVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0));

    vm.prank(VAULT_OWNER);
    v.setVaultOwnerFeeBasisPoint(1234);
    assertEq(v.vaultOwnerFeeBasisPoint(), 1234);

    vm.startPrank(VAULT_OWNER);
    address fakeNfpm = makeAddr("nfpmFee");
    bytes memory stratData = abi.encode(fakeNfpm, uint256(1), address(tA), address(tB), 50e18, 50e18);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    v.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    uint256 shares = v.balanceOf(VAULT_OWNER);

    vm.recordLogs();
    vm.prank(VAULT_OWNER);
    v.withdraw(shares, [uint256(0), uint256(0), uint256(0), uint256(0)], false);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    bytes32 evSig = keccak256("ExitVaultOwnerFeeBps(uint16)");
    bool found;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter == address(v) && logs[i].topics.length > 0 && logs[i].topics[0] == evSig) {
        assertEq(abi.decode(logs[i].data, (uint256)), 1234);
        found = true;
        break;
      }
    }
    assertTrue(found, "ExitVaultOwnerFeeBps must be emitted from vault during delegatecall exit");
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

  // ==================== Native ETH / WETH Tests ====================

  /// @dev Creates a fresh vault with [tokenA, mockWeth] tokens and 100e18 of each.
  ///      ETH is deposited via mockWeth.deposit() so MockWETH9 holds real ETH to back withdrawals.
  function _setupWethVault() internal returns (SharedVault wv) {
    wv = new SharedVault();

    // Wrap 100e18 ETH → WETH; test contract gets the WETH and transfers to vault
    tokenA.mint(address(this), 100e18);
    vm.deal(address(this), 100e18);
    mockWeth.deposit{ value: 100e18 }();

    tokenA.transfer(address(wv), 100e18);
    mockWeth.transfer(address(wv), 100e18);

    address[4] memory wvTokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    wv.initialize(
      "WETH Vault",
      wvTokens,
      initAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(mockWeth)
    );
    vm.stopPrank();
    // VAULT_OWNER now has all shares = 100e18 * SHARES_PRECISION
  }

  /// @notice Depositing with msg.value wraps ETH to WETH inside the vault
  function test_deposit_eth_wraps_to_weth() public {
    SharedVault wethVault = _setupWethVault();

    tokenA.mint(DEPOSITOR, 50e18);
    vm.deal(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(wethVault), type(uint256).max);

    // Deposit 50e18 tokenA + 50e18 ETH (→ WETH). Proportional: 50/100 ratio → exact match.
    uint256[4] memory amounts = [uint256(50e18), uint256(50e18), uint256(0), uint256(0)];
    uint256 shares = wethVault.deposit{ value: 50e18 }(amounts, 0);
    vm.stopPrank();

    assertGt(shares, 0);
    assertEq(wethVault.balanceOf(DEPOSITOR), shares);

    // Vault gained 50e18 WETH from wrapped ETH
    assertEq(mockWeth.balanceOf(address(wethVault)), 150e18);
    // Depositor's ETH is fully consumed
    assertEq(DEPOSITOR.balance, 0);
  }

  /// @notice Proportional deposit: only the needed fraction of WETH is consumed; excess ETH is refunded
  function test_deposit_eth_excess_refund() public {
    SharedVault wethVault = _setupWethVault();
    // State: 100e18 tokenA + 100e18 WETH, totalSupply = 100e18 * SHARES_PRECISION

    // Depositor sends 40e18 tokenA + 80e18 ETH, but the binding constraint is tokenA (40/100 = 40%)
    // transferAmounts = [40e18, 40e18]; excess WETH = 80e18 - 40e18 = 40e18 refunded as ETH
    tokenA.mint(DEPOSITOR, 40e18);
    vm.deal(DEPOSITOR, 80e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(wethVault), type(uint256).max);

    uint256[4] memory amounts = [uint256(40e18), uint256(80e18), uint256(0), uint256(0)];
    wethVault.deposit{ value: 80e18 }(amounts, 0);
    vm.stopPrank();

    // 40e18 ETH refunded; depositor paid net 40e18 ETH
    assertEq(DEPOSITOR.balance, 40e18);
    // Vault received only 40e18 WETH (not 80e18)
    assertEq(mockWeth.balanceOf(address(wethVault)), 140e18);
  }

  /// @notice Sending ETH when no WETH token is configured in the vault reverts
  function test_deposit_eth_fails_weth_not_configured() public {
    // `vault` was initialized with weth = address(0): no WETH slot
    vm.deal(DEPOSITOR, 1 ether);
    uint256[4] memory amounts = [uint256(0), uint256(1 ether), uint256(0), uint256(0)];
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.deposit{ value: 1 ether }(amounts, 0);
  }

  /// @notice msg.value must equal amounts[wethIndex]; mismatch reverts
  function test_deposit_eth_fails_wrong_amount() public {
    SharedVault wethVault = _setupWethVault();
    vm.deal(DEPOSITOR, 60e18);

    uint256[4] memory amounts = [uint256(0), uint256(50e18), uint256(0), uint256(0)];
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    // msg.value (60e18) != amounts[wethIndex] (50e18)
    wethVault.deposit{ value: 60e18 }(amounts, 0);
  }

  /// @notice Withdraw with unwrap=true: WETH is unwrapped and caller receives native ETH
  function test_withdraw_unwrap_true_sends_native_eth() public {
    SharedVault wethVault = _setupWethVault();
    uint256 shares = wethVault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    uint256 ethBefore = VAULT_OWNER.balance;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = wethVault.withdraw(shares, minAmounts, true);

    // VAULT_OWNER received native ETH for the WETH portion
    assertEq(VAULT_OWNER.balance - ethBefore, received[1]);
    assertGt(received[1], 0);
    // No WETH tokens transferred
    assertEq(mockWeth.balanceOf(VAULT_OWNER), 0);
    // tokenA transferred as ERC20
    assertEq(tokenA.balanceOf(VAULT_OWNER), received[0]);
  }

  /// @notice Withdraw with unwrap=false: WETH stays as an ERC20 token, no native ETH sent
  function test_withdraw_unwrap_false_keeps_weth_token() public {
    SharedVault wethVault = _setupWethVault();
    uint256 shares = wethVault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    uint256[4] memory received = wethVault.withdraw(shares, minAmounts, false);

    // VAULT_OWNER received WETH tokens (not native ETH)
    assertEq(mockWeth.balanceOf(VAULT_OWNER), received[1]);
    assertGt(received[1], 0);
    // No native ETH received
    assertEq(VAULT_OWNER.balance, 0);
    // tokenA received as ERC20
    assertEq(tokenA.balanceOf(VAULT_OWNER), received[0]);
  }

  /// @notice When WETH transferAmount rounds to zero (dust), wrapped ETH is fully refunded
  /// @dev Constructs: tokenA=1e18, mockWeth=1 wei → totalSupply=1e36
  ///      Deposit 1 wei ETH: shares=1e18, transferAmounts[weth]=mulDiv(1e18,1,1e36)=0
  ///      Before fix: wrapped ETH locked in vault. After fix: fully refunded.
  function test_deposit_eth_dust_amount_refunded() public {
    // Vault: 1e18 tokenA, 1 wei WETH — totalSupply = 1e36 (tokenA * SHARES_PRECISION)
    SharedVault wv = new SharedVault();
    tokenA.mint(address(this), 1e18);
    vm.deal(address(this), 100 ether);
    mockWeth.deposit{ value: 1 }(); // 1 wei WETH backed by 1 wei ETH

    tokenA.transfer(address(wv), 1e18);
    mockWeth.transfer(address(wv), 1);

    address[4] memory wvTokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1e18), uint256(1), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    wv.initialize(
      "Dust Vault",
      wvTokens,
      initAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(mockWeth)
    );
    vm.stopPrank();
    // totalSupply = 1e18 * 1e18 = 1e36

    address depositor = makeAddr("dustDepositor");
    vm.deal(depositor, 1 wei);
    tokenA.mint(depositor, 1);

    vm.startPrank(depositor);
    tokenA.approve(address(wv), 1);

    // amounts[1] = 1 wei ETH; transferAmounts[1] will round to zero
    uint256[4] memory amounts = [uint256(1), uint256(1), uint256(0), uint256(0)];
    uint256 sharesBefore = wv.balanceOf(depositor);
    uint256 ethBefore = depositor.balance;

    wv.deposit{ value: 1 }(amounts, 0);
    vm.stopPrank();

    // Depositor receives shares (non-zero — tokenA contribution)
    assertGt(wv.balanceOf(depositor), sharesBefore, "should receive shares");
    // The 1 wei ETH must be fully refunded (transferAmounts[weth] was 0)
    assertEq(depositor.balance, ethBefore, "dust ETH must be refunded, not locked");
    // Vault WETH balance unchanged (1 wei — no extra WETH was actually deposited)
    assertEq(mockWeth.balanceOf(address(wv)), 1, "vault WETH balance unchanged");
  }

  // ==================== Double-Dilution Regression Tests ====================

  /// @dev Helper: creates a fresh vault with LP strategy, two equal depositors, and an LP position.
  ///      Each user deposits `depositPerUser` of each token.
  ///      Then `lpAmount` of each token is moved into a mock LP position.
  ///      Final state: idle = 2*depositPerUser - lpAmount, LP = lpAmount, total = 2*depositPerUser per token.
  ///      Alice and Bob each hold 50% of shares → each entitled to `depositPerUser` per token.
  function _setupLPVault(
    uint256 depositPerUser,
    uint256 lpAmount
  ) internal returns (SharedVault v, MockERC20 tA, MockERC20 tB, MockLPPool lpPoolContract) {
    lpPoolContract = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(lpPoolContract));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(lpStrategy);
    address[] memory callers = new address[](0);
    cm.initialize(address(this), targets, callers, address(this));

    v = new SharedVault();
    tA = new MockERC20("Token A", "A");
    tB = new MockERC20("Token B", "B");

    // Alice (VAULT_OWNER) seeds vault
    tA.mint(address(this), depositPerUser);
    tB.mint(address(this), depositPerUser);
    tA.transfer(address(v), depositPerUser);
    tB.transfer(address(v), depositPerUser);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [depositPerUser, depositPerUser, uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    v.initialize("TestVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0));
    vm.stopPrank();

    // Bob deposits the same amounts → gets equal shares
    address bob = makeAddr("bob");
    tA.mint(bob, depositPerUser);
    tB.mint(bob, depositPerUser);
    vm.startPrank(bob);
    tA.approve(address(v), type(uint256).max);
    tB.approve(address(v), type(uint256).max);
    uint256[4] memory bobDeposit = [depositPerUser, depositPerUser, uint256(0), uint256(0)];
    v.deposit(bobDeposit, 0);
    vm.stopPrank();

    // Move lpAmount of each into LP via strategy execute
    if (lpAmount > 0) {
      vm.startPrank(VAULT_OWNER);
      address fakeNfpm = makeAddr("nfpm");
      bytes memory stratData = abi.encode(fakeNfpm, uint256(1), address(tA), address(tB), lpAmount, lpAmount);
      ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
      actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
      v.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
      vm.stopPrank();
    }
  }

  /// @notice Regression: withdraw with active LP must not double-dilute the LP exit return.
  /// Each user deposits 100e18 per token, vault creates 100e18 LP.
  /// Final state: idle=100e18, LP=100e18, total=200e18 per token, 50/50 shares.
  /// Alice's 50% = 100e18 per token.
  /// Before fix: exitProportional returns 50e18 → idle=150e18 → amounts=50/100*150=75e18 (WRONG).
  /// After fix:  amounts = 50/100*100(original idle) + 50(LP return) = 100e18 (CORRECT).
  function test_withdraw_no_double_dilution_with_lp() public {
    // depositPerUser=100e18, lpAmount=100e18
    // total=200e18, idle=100e18, LP=100e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB, ) = _setupLPVault(100e18, 100e18);

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    assertEq(aliceShares, v.INITIAL_SHARES());
    assertEq(v.totalSupply(), v.INITIAL_SHARES() * 2);

    // Verify total balances
    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 200e18, "total A = 200e18");
    assertEq(totalBal[1], 200e18, "total B = 200e18");

    // Preview: Alice's 50% of 200e18 = 100e18
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 100e18, "preview A = 50% of 200e18");
    assertEq(preview[1], 100e18, "preview B = 50% of 200e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    // Core assertion: Alice gets her full proportional share
    assertEq(received[0], 100e18, "Alice must receive 100e18 A (not 75e18)");
    assertEq(received[1], 100e18, "Alice must receive 100e18 B (not 75e18)");
    assertEq(received[0], preview[0], "actual must match preview for A");
    assertEq(received[1], preview[1], "actual must match preview for B");

    // Bob withdraws the remainder — vault must be perfectly drained
    address bob = makeAddr("bob");
    uint256[4] memory bobPreview = v.previewWithdraw(v.balanceOf(bob));
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 100e18, "Bob must receive 100e18 A");
    assertEq(bobReceived[1], 100e18, "Bob must receive 100e18 B");
    assertEq(bobReceived[0], bobPreview[0], "Bob actual must match preview for A");
    assertEq(bobReceived[1], bobPreview[1], "Bob actual must match preview for B");

    assertEq(v.totalSupply(), 0, "all shares burned");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  /// @notice Heavy LP allocation — matches the bug report's Alice/Bob scenario.
  /// Each user deposits 500e18, vault creates 900e18 LP.
  /// Final: idle=100e18, LP=900e18, total=1000e18 per token.
  /// Alice's 50% = 500e18.
  /// Before fix: exit returns 450 → idle=550 → amounts=50%*550=275 (WRONG).
  /// After fix:  amounts = 50%*100 + 450 = 500 (CORRECT).
  function test_withdraw_heavy_lp_no_double_dilution() public {
    // depositPerUser=500e18, lpAmount=900e18
    // total=1000e18, idle=100e18, LP=900e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB, ) = _setupLPVault(500e18, 900e18);

    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 1000e18, "total A");
    assertEq(totalBal[1], 1000e18, "total B");
    assertEq(tA.balanceOf(address(v)), 100e18, "idle A = 100e18");

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 500e18, "preview A = 50% of 1000e18");
    assertEq(preview[1], 500e18, "preview B = 50% of 1000e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    assertEq(received[0], 500e18, "Alice A = 500e18 (not 275e18)");
    assertEq(received[1], 500e18, "Alice B = 500e18 (not 275e18)");
    assertEq(received[0], preview[0], "match preview A");
    assertEq(received[1], preview[1], "match preview B");

    // Bob gets the other half — vault drains cleanly
    address bob = makeAddr("bob");
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 500e18, "Bob A");
    assertEq(bobReceived[1], 500e18, "Bob B");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  /// @notice Edge case: vault has zero idle, 100% LP.
  /// depositPerUser=50e18, lpAmount=100e18 → idle=0, LP=100e18, total=100e18.
  /// Alice's 50% = 50e18.
  function test_withdraw_zero_idle_all_lp_no_double_dilution() public {
    // depositPerUser=50e18, lpAmount=100e18
    // total=100e18, idle=0, LP=100e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB, ) = _setupLPVault(50e18, 100e18);

    assertEq(tA.balanceOf(address(v)), 0, "idle A = 0");
    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 100e18, "total A = 100e18");

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 50e18, "preview A = 50% of 100e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    assertEq(received[0], 50e18, "Alice A");
    assertEq(received[1], 50e18, "Alice B");
    assertEq(received[0], preview[0], "match preview A");

    // Bob gets remainder
    address bob = makeAddr("bob");
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 50e18, "Bob A");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  // ==================== execute() — DELEGATECALL + token changes ====================

  /// @notice DELEGATECALL returning an empty PositionChange[] is the token-change case:
  ///         the strategy runs in vault context (e.g., harvest+swap) and only vault token
  ///         balances change. The vault sees the idle balance difference with no position tracking.
  function test_execute_delegatecall_token_changes_empty_position_array() public {
    // Simulate a harvest: externally mint tokenA into vault before the strategy "runs"
    // (in a real harvest the strategy would collect fees and they'd land in the vault)
    uint256 harvestAmount = 5e18;
    tokenA.mint(address(vault), harvestAmount);
    uint256 balanceBefore = tokenA.balanceOf(address(vault));

    vm.startPrank(VAULT_OWNER);
    // MockSharedStrategy.execute() returns empty PositionChange[] — simulates a token-only op
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(0)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    // No position changes expected
    assertEq(vault.getPositionCount(), 0, "no positions should be tracked");
    // Token balance reflects the externally-added harvest (vault always sees current idle balance)
    assertEq(tokenA.balanceOf(address(vault)), balanceBefore, "token balance unchanged by empty strategy");
  }

  /// @notice DELEGATECALL with non-empty PositionChange[] → LP position tracked.
  ///         This is the existing behavior confirmed as the "position change" case.
  function test_execute_delegatecall_position_changes_tracked() public {
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));

    vm.startPrank(address(this));
    address[] memory extraTargets1 = new address[](1);
    extraTargets1[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets1, true);
    vm.stopPrank();

    address mockNfpm = address(0xDEAD);
    uint256 tokenId = 1;

    // Give vault some tokens so the LP deposit can pull them
    tokenA.mint(address(vault), 10e18);
    tokenB.mint(address(pool), 10e18); // pool needs tokenB to return on exit

    vm.startPrank(VAULT_OWNER);
    bytes memory stratData = abi.encode(
      mockNfpm,
      tokenId,
      address(tokenA),
      address(tokenB),
      uint256(10e18),
      uint256(0)
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "one LP position should be tracked");
    (address strategy, address nfpm, uint256 tid, , ) = vault.getPosition(0);
    assertEq(strategy, address(lpStrategy), "strategy stored correctly");
    assertEq(nfpm, mockNfpm, "nfpm stored correctly");
    assertEq(tid, tokenId, "tokenId stored correctly");
  }

  // ==================== execute() — CALL_WITH_POSITIONS ====================

  /// @notice CALL_WITH_POSITIONS: direct call returns PositionChange[] → LP position added.
  function test_execute_call_with_positions_adds_position() public {
    address mockNfpm = address(0xBEEF);
    uint256 tokenId = 42;

    bytes memory callData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (mockNfpm, tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "position should be added");
    (address strategy, address nfpm, uint256 tid, address t0, address t1) = vault.getPosition(0);
    assertEq(strategy, address(directCreator), "strategy is the direct creator target");
    assertEq(nfpm, mockNfpm);
    assertEq(tid, tokenId);
    assertEq(t0, address(tokenA));
    assertEq(t1, address(tokenB));
  }

  /// @notice CALL_WITH_POSITIONS: direct call returns PositionChange[] with isAdd=false → position removed.
  function test_execute_call_with_positions_removes_position() public {
    // First add a position via DELEGATECALL
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory extraTargets2 = new address[](1);
    extraTargets2[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets2, true);

    address mockNfpm = address(0xBEEF);
    uint256 tokenId = 99;

    tokenA.mint(address(vault), 10e18);
    tokenB.mint(address(pool), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory addData = abi.encode(mockNfpm, tokenId, address(tokenA), address(tokenB), uint256(10e18), uint256(0));
    ISharedVault.Action[] memory addActions = new ISharedVault.Action[](1);
    addActions[0] = ISharedVault.Action(address(lpStrategy), addData, ISharedCommon.CallType.DELEGATECALL);
    vault.execute(addActions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "position added");

    // Now remove via CALL_WITH_POSITIONS
    bytes memory removeCallData = abi.encodeCall(
      MockDirectPositionCreator.removePosition,
      (mockNfpm, tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory removeActions = new ISharedVault.Action[](1);
    removeActions[0] = ISharedVault.Action(
      address(directCreator),
      removeCallData,
      ISharedCommon.CallType.CALL_WITH_POSITIONS
    );
    vault.execute(removeActions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "position should be removed");
  }

  /// @notice CALL_WITH_POSITIONS with empty PositionChange[] result → no tracking change.
  function test_execute_call_with_positions_empty_result_no_change() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.noChanges, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "no positions should be added");
  }

  /// @notice CALL_WITH_POSITIONS: target call reverts → execute reverts with the error message.
  function test_execute_call_with_positions_reverts_on_failure() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.alwaysFail, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert("DirectCreator: always fails");
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  /// @notice CALL_WITH_POSITIONS: non-whitelisted target → reverts with InvalidTarget.
  function test_execute_call_with_positions_non_whitelisted_target() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.noChanges, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    // Use failingStrategy address which is NOT whitelisted
    actions[0] = ISharedVault.Action(address(failingStrategy), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();
  }

  /// @notice Mixed batch: DELEGATECALL (position) + CALL (swap) + CALL_WITH_POSITIONS (position) in one execute().
  function test_execute_mixed_batch_all_three_call_types() public {
    // Setup: whitelist lpStrategy
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory extraTargets3 = new address[](1);
    extraTargets3[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets3, true);

    // Prepare tokens
    tokenA.mint(address(vault), 20e18);
    tokenB.mint(address(pool), 10e18);
    tokenB.mint(address(swapTarget), 5e18);

    address delegatecallNfpm = address(0xAAAA);
    address callWithPositionsNfpm = address(0xBBBB);

    // Action 1: DELEGATECALL — strategy creates LP position
    bytes memory dcData = abi.encode(
      delegatecallNfpm,
      uint256(1),
      address(tokenA),
      address(tokenB),
      uint256(10e18),
      uint256(0)
    );

    // Action 2: CALL — token swap tokenA → tokenB
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 5e18));
    bytes memory swapData = abi.encode(address(tokenA), address(tokenB), 5e18, uint256(0), swapCalldata);

    // Action 3: CALL_WITH_POSITIONS — direct call creates another position
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (callWithPositionsNfpm, 2, address(tokenA), address(tokenB))
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](3);
    actions[0] = ISharedVault.Action(address(lpStrategy), dcData, ISharedCommon.CallType.DELEGATECALL);
    actions[1] = ISharedVault.Action(address(swapTarget), swapData, ISharedCommon.CallType.CALL);
    actions[2] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.startPrank(VAULT_OWNER);
    vault.execute(actions, new ISharedVault.PositionStrategyUpdate[](0));
    vm.stopPrank();

    // Two LP positions tracked (one from DELEGATECALL, one from CALL_WITH_POSITIONS)
    assertEq(vault.getPositionCount(), 2, "two positions should be tracked");
    // Swap was also successful
    assertGt(tokenB.balanceOf(address(vault)), 0, "tokenB balance increased from swap");
  }
}
