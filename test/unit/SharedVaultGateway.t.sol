// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultGateway } from "../../contracts/shared-vault/core/SharedVaultGateway.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ==================== Mock Contracts ====================

contract GatewayMockWETH9 {
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

contract GatewayMockERC20 {
  string public name;
  string public symbol;
  uint8 public immutable decimals;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name, string memory _symbol, uint8 _decimals) {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
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

/// @dev Simulates a swap aggregator router. Given pre-funded output tokens, it executes
///      a 1:rate swap. Rate is configurable per pair at deploy time, defaults to 1:1.
contract MockAggregatorRouter {
  struct Rate {
    address tokenIn;
    address tokenOut;
    uint256 rateNum; // numerator: outAmount = inAmount * rateNum / rateDen
    uint256 rateDen; // denominator
  }

  mapping(bytes32 => Rate) public rates;

  function setRate(address tokenIn, address tokenOut, uint256 num, uint256 den) external {
    bytes32 key = keccak256(abi.encodePacked(tokenIn, tokenOut));
    rates[key] = Rate(tokenIn, tokenOut, num, den);
  }

  /// @notice Called by gateway with arbitrary calldata. We decode our own params.
  function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
    GatewayMockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    bytes32 key = keccak256(abi.encodePacked(tokenIn, tokenOut));
    Rate memory r = rates[key];
    uint256 amountOut;
    if (r.rateDen > 0) {
      amountOut = (amountIn * r.rateNum) / r.rateDen;
    } else {
      amountOut = amountIn; // default 1:1
    }
    GatewayMockERC20(tokenOut).transfer(msg.sender, amountOut);
  }

  /// @notice Swaps the caller's full approved balance of tokenIn. Used when exact amount is unknown
  ///         at calldata-build time (e.g. post-withdraw amounts).
  function swapAll(address tokenIn, address tokenOut) external {
    uint256 amountIn = GatewayMockERC20(tokenIn).allowance(msg.sender, address(this));
    uint256 bal = GatewayMockERC20(tokenIn).balanceOf(msg.sender);
    if (amountIn > bal) amountIn = bal;
    if (amountIn == 0) return;
    GatewayMockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    bytes32 key = keccak256(abi.encodePacked(tokenIn, tokenOut));
    Rate memory r = rates[key];
    uint256 amountOut;
    if (r.rateDen > 0) {
      amountOut = (amountIn * r.rateNum) / r.rateDen;
    } else {
      amountOut = amountIn;
    }
    GatewayMockERC20(tokenOut).transfer(msg.sender, amountOut);
  }
}

// ==================== Test Contract ====================

contract SharedVaultGatewayTest is TestCommon {
  SharedVault public vault;
  SharedVaultGateway public gateway;
  SharedConfigManager public configManager;
  MockAggregatorRouter public router;

  GatewayMockERC20 public tokenA; // vault token 0
  GatewayMockERC20 public tokenB; // vault token 1
  GatewayMockERC20 public tokenC; // vault token 2
  GatewayMockERC20 public tokenD; // vault token 3
  GatewayMockERC20 public tokenX; // external non-vault input token
  GatewayMockWETH9 public mockWeth;

  address public constant VAULT_OWNER = address(0xA1);
  address public constant ALICE = address(0xA2);
  address public constant BOB = address(0xA3);

  function setUp() public {
    // Deploy tokens
    tokenA = new GatewayMockERC20("Token A", "TKA", 18);
    tokenB = new GatewayMockERC20("Token B", "TKB", 18);
    tokenC = new GatewayMockERC20("Token C", "TKC", 6); // USDC-like
    tokenD = new GatewayMockERC20("Token D", "TKD", 18);
    tokenX = new GatewayMockERC20("Token X", "TKX", 18);
    mockWeth = new GatewayMockWETH9();

    // Deploy aggregator router
    router = new MockAggregatorRouter();

    // Deploy config manager
    configManager = new SharedConfigManager();
    address[] memory targets = new address[](0);
    address[] memory callers = new address[](0);
    configManager.initialize(address(this), targets, callers, address(this));

    // Deploy and initialize vault with 4 tokens
    vault = new SharedVault();
    _seedVault();

    // Deploy and initialize gateway
    gateway = new SharedVaultGateway();
    gateway.initialize(address(this), address(router), address(mockWeth));
  }

  function _seedVault() internal {
    tokenA.mint(address(this), 1000e18);
    tokenB.mint(address(this), 2000e18);
    tokenC.mint(address(this), 500e6);
    tokenD.mint(address(this), 1000e18);

    GatewayMockERC20(address(tokenA)).transfer(address(vault), 1000e18);
    GatewayMockERC20(address(tokenB)).transfer(address(vault), 2000e18);
    GatewayMockERC20(address(tokenC)).transfer(address(vault), 500e6);
    GatewayMockERC20(address(tokenD)).transfer(address(vault), 1000e18);

    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initialAmounts = [uint256(1000e18), uint256(2000e18), uint256(500e6), uint256(1000e18)];

    vm.prank(VAULT_OWNER);
    vault.initialize(
      "4-Token Vault",
      vaultTokens,
      initialAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(0)
    );
  }

  // ==================== Helpers ====================

  function _buildSwapCalldata(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) internal pure returns (bytes memory) {
    return abi.encodeCall(MockAggregatorRouter.swap, (tokenIn, tokenOut, amountIn));
  }

  function _buildSwapAllCalldata(address tokenIn, address tokenOut) internal pure returns (bytes memory) {
    return abi.encodeCall(MockAggregatorRouter.swapAll, (tokenIn, tokenOut));
  }

  function _approveGateway(address token, address user) internal {
    vm.prank(user);
    GatewayMockERC20(token).approve(address(gateway), type(uint256).max);
  }

  function _approveGatewayAll(address user) internal {
    _approveGateway(address(tokenA), user);
    _approveGateway(address(tokenB), user);
    _approveGateway(address(tokenC), user);
    _approveGateway(address(tokenD), user);
    _approveGateway(address(tokenX), user);
    _approveGateway(address(vault), user);
  }

  // ==================== Initialization Tests ====================

  function test_initialize_success() public view {
    assertEq(gateway.swapRouter(), address(router));
    assertEq(gateway.weth(), address(mockWeth));
    assertEq(gateway.owner(), address(this));
  }

  function test_initialize_fail_zero_owner() public {
    SharedVaultGateway gw = new SharedVaultGateway();
    vm.expectRevert(SharedVaultGateway.ZeroAddress.selector);
    gw.initialize(address(0), address(router), address(mockWeth));
  }

  function test_initialize_fail_zero_router() public {
    SharedVaultGateway gw = new SharedVaultGateway();
    vm.expectRevert(SharedVaultGateway.ZeroAddress.selector);
    gw.initialize(address(this), address(0), address(mockWeth));
  }

  function test_initialize_fail_zero_weth() public {
    SharedVaultGateway gw = new SharedVaultGateway();
    vm.expectRevert(SharedVaultGateway.ZeroAddress.selector);
    gw.initialize(address(this), address(router), address(0));
  }

  // ==================== Admin Tests ====================

  function test_setSwapRouter() public {
    address newRouter = address(0xBEEF);
    gateway.setSwapRouter(newRouter);
    assertEq(gateway.swapRouter(), newRouter);
  }

  function test_setSwapRouter_fail_zero() public {
    vm.expectRevert(SharedVaultGateway.InvalidSwapRouter.selector);
    gateway.setSwapRouter(address(0));
  }

  function test_setSwapRouter_fail_unauthorized() public {
    vm.prank(ALICE);
    vm.expectRevert();
    gateway.setSwapRouter(address(0xBEEF));
  }

  function test_setPaused() public {
    gateway.setPaused(true);
    assertTrue(gateway.paused());
    gateway.setPaused(false);
    assertFalse(gateway.paused());
  }

  // ==================== SwapAndDeposit: No Swaps (Direct Deposit) ====================

  function test_swapAndDeposit_no_swaps_direct_deposit() public {
    // Alice has all 4 vault tokens in correct ratio and deposits directly through gateway
    // Vault ratio: 1000A : 2000B : 500C : 1000D
    // Deposit: 100A : 200B : 50C : 100D (10% of pool)
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // Use swaps just to pull tokens (no swapData)
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps[1] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "Should receive shares");
    assertEq(vault.balanceOf(ALICE), shares, "Alice receives shares");
    assertEq(tokenA.balanceOf(address(gateway)), 0, "No tokenA leftover in gateway");
    assertEq(tokenB.balanceOf(address(gateway)), 0, "No tokenB leftover in gateway");
    assertEq(tokenC.balanceOf(address(gateway)), 0, "No tokenC leftover in gateway");
    assertEq(tokenD.balanceOf(address(gateway)), 0, "No tokenD leftover in gateway");
  }

  // ==================== SwapAndDeposit: Single Token → 4 Vault Tokens ====================

  function test_swapAndDeposit_single_token_to_four() public {
    // Alice has only tokenX and wants to deposit into the 4-token vault
    // She swaps tokenX → A, B, C, D via the aggregator, then deposits

    // Fund router with output tokens
    tokenA.mint(address(router), 100e18);
    tokenB.mint(address(router), 200e18);
    tokenC.mint(address(router), 50e6);
    tokenD.mint(address(router), 100e18);

    // Set rates: 1 X = 1 A, 1 X = 2 B, 1 X = 0.5 C (6 dec), 1 X = 1 D
    router.setRate(address(tokenX), address(tokenA), 1, 1);
    router.setRate(address(tokenX), address(tokenB), 2, 1);
    router.setRate(address(tokenX), address(tokenC), 50e6, 100e18); // 0.5 C per X in decimals
    router.setRate(address(tokenX), address(tokenD), 1, 1);

    // Alice needs: 100A + 200B + 50C + 100D
    // At above rates: 100X→100A, 100X→200B, 100X→50C, 100X→100D = 400X total
    tokenX.mint(ALICE, 400e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenA),
      90e18,
      _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenB),
      180e18,
      _buildSwapCalldata(address(tokenX), address(tokenB), 100e18)
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenC),
      45e6,
      _buildSwapCalldata(address(tokenX), address(tokenC), 100e18)
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenD),
      90e18,
      _buildSwapCalldata(address(tokenX), address(tokenD), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "Should receive shares");
    assertEq(vault.balanceOf(ALICE), shares, "Alice receives shares");
    assertEq(tokenX.balanceOf(address(gateway)), 0, "No leftover tokenX in gateway");
  }

  // ==================== SwapAndDeposit: Partial Swaps With Leftovers ====================

  function test_swapAndDeposit_excess_tokens_returned_to_user() public {
    // Vault ratio 1000A:2000B → 1:2. Alice over-provides tokenA but exact tokenB.
    // She swaps nothing — just deposits 150A:200B. The binding ratio is B (200/2000 = 10%).
    // transferAmount for A = 10% * 1000 = 100. Leftover: 50A returned.

    tokenA.mint(ALICE, 150e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 150e18, address(tokenA), 0, "");
    swaps[1] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "Should receive shares");
    uint256 aliceAAfter = tokenA.balanceOf(ALICE);
    // Alice should get back her excess tokenA
    assertGt(aliceAAfter, 0, "Alice should receive leftover tokenA");
    assertEq(tokenA.balanceOf(address(gateway)), 0, "Gateway has no residual tokenA");
  }

  // ==================== SwapAndDeposit: Swap + Deposit Combined ====================

  function test_swapAndDeposit_swap_one_token_to_complete_ratio() public {
    // Vault: 1000A:2000B:500C:1000D. Alice has A, B, D but no C.
    // She swaps some extra tokenA to tokenC via the aggregator, then deposits.

    tokenA.mint(ALICE, 200e18); // extra A to swap 100A→50C
    tokenB.mint(ALICE, 200e18);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // Fund router with tokenC
    tokenC.mint(address(router), 100e6);
    router.setRate(address(tokenA), address(tokenC), 50e6, 100e18); // 100A → 50C

    // Swap 1: 100A → 50C, then the remaining tokens (100A, 200B, 50C, 100D) deposit
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      100e18,
      address(tokenC),
      45e6,
      _buildSwapCalldata(address(tokenA), address(tokenC), 100e18)
    );
    // Pull remaining tokens (no swap needed, just pull)
    swaps[1] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "Should receive shares");
    assertEq(vault.balanceOf(ALICE), shares);
    assertEq(tokenA.balanceOf(address(gateway)), 0, "No gateway residual");
    assertEq(tokenC.balanceOf(address(gateway)), 0, "No gateway residual");
  }

  // ==================== SwapAndDeposit: minShares guard ====================

  function test_swapAndDeposit_fail_min_shares() public {
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps[1] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: type(uint256).max, // impossibly high
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(); // vault will revert with InsufficientShares
    gateway.swapAndDeposit(params);
  }

  // ==================== SwapAndDeposit: Swap slippage check ====================

  function test_swapAndDeposit_fail_swap_slippage() public {
    tokenX.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // Router funded but rate is bad: 100X → 50A (0.5:1)
    tokenA.mint(address(router), 50e18);
    router.setRate(address(tokenX), address(tokenA), 1, 2);

    // amountOutMin = 90A, but router will only give 50A → SlippageExceeded
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenA),
      90e18,
      _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.SlippageExceeded.selector, 0));
    gateway.swapAndDeposit(params);
  }

  // ==================== SwapAndDeposit: Failed swap reverts ====================

  function test_swapAndDeposit_fail_swap_failed() public {
    tokenX.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // Router has no output tokens → swap will fail
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenA),
      0,
      _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.SwapFailed.selector, 0));
    gateway.swapAndDeposit(params);
  }

  // ==================== SwapAndDeposit: Paused ====================

  function test_swapAndDeposit_fail_when_paused() public {
    gateway.setPaused(true);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](0);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert();
    gateway.swapAndDeposit(params);
  }

  // ==================== WithdrawAndSwap: Basic ====================

  function _depositForAlice() internal returns (uint256 shares) {
    // Give Alice exact proportional amounts and deposit via gateway
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps[1] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    shares = gateway.swapAndDeposit(params);
  }

  function test_withdrawAndSwap_no_swaps() public {
    uint256 shares = _depositForAlice();

    // Alice withdraws with no swaps — receives vault tokens directly
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](0);
    address[] memory sweepTokens = new address[](0);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: sweepTokens
    });

    vm.prank(ALICE);
    uint256[4] memory amounts = gateway.withdrawAndSwap(params);

    assertGt(amounts[0], 0, "Should receive tokenA");
    assertGt(amounts[1], 0, "Should receive tokenB");
    assertGt(amounts[2], 0, "Should receive tokenC");
    assertGt(amounts[3], 0, "Should receive tokenD");

    // Tokens swept to Alice
    assertGt(tokenA.balanceOf(ALICE), 0, "Alice has tokenA");
    assertGt(tokenB.balanceOf(ALICE), 0, "Alice has tokenB");
    assertGt(tokenC.balanceOf(ALICE), 0, "Alice has tokenC");
    assertGt(tokenD.balanceOf(ALICE), 0, "Alice has tokenD");

    // Gateway is clean
    assertEq(tokenA.balanceOf(address(gateway)), 0);
    assertEq(tokenB.balanceOf(address(gateway)), 0);
    assertEq(tokenC.balanceOf(address(gateway)), 0);
    assertEq(tokenD.balanceOf(address(gateway)), 0);
    assertEq(vault.balanceOf(ALICE), 0, "All shares burned");
  }

  // ==================== WithdrawAndSwap: Swap vault tokens to single output ====================

  function test_withdrawAndSwap_consolidate_to_single_token() public {
    uint256 shares = _depositForAlice();

    // After withdraw, Alice wants to convert B, C, D into tokenA
    // She has B, C, D from withdraw and swaps them all → A
    tokenA.mint(address(router), 1000e18); // fund router
    router.setRate(address(tokenB), address(tokenA), 1, 2); // 2B → 1A
    router.setRate(address(tokenC), address(tokenA), 100e18, 50e6); // 50C → 100A
    router.setRate(address(tokenD), address(tokenA), 1, 1); // 1D → 1A

    // Use amountIn=0 to swap full balance of each, with swapAll calldata
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](3);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenB),
      0,
      address(tokenA),
      0,
      _buildSwapAllCalldata(address(tokenB), address(tokenA))
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenC),
      0,
      address(tokenA),
      0,
      _buildSwapAllCalldata(address(tokenC), address(tokenA))
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(tokenD),
      0,
      address(tokenA),
      0,
      _buildSwapAllCalldata(address(tokenD), address(tokenA))
    );

    address[] memory sweepTokens = new address[](0);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: sweepTokens
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    // Alice receives tokenA (her original + swapped B, C, D)
    assertGt(tokenA.balanceOf(ALICE), 0, "Alice should have tokenA");
    // B, C, D should be zero or near-zero (all swapped)
    assertEq(tokenB.balanceOf(ALICE), 0, "tokenB swapped away");
    assertEq(tokenC.balanceOf(ALICE), 0, "tokenC swapped away");
    assertEq(tokenD.balanceOf(ALICE), 0, "tokenD swapped away");

    // Gateway clean
    assertEq(tokenA.balanceOf(address(gateway)), 0);
    assertEq(tokenB.balanceOf(address(gateway)), 0);
    assertEq(tokenC.balanceOf(address(gateway)), 0);
    assertEq(tokenD.balanceOf(address(gateway)), 0);
  }

  // ==================== WithdrawAndSwap: Slippage on post-withdraw swap ====================

  function test_withdrawAndSwap_fail_swap_slippage() public {
    uint256 shares = _depositForAlice();

    // Bad rate: tokenB → tokenA at 0.1:1 but minOut demands 1:1
    tokenA.mint(address(router), 1000e18);
    router.setRate(address(tokenB), address(tokenA), 1, 10);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenB),
      0,
      address(tokenA),
      100e18, // expect ≥100A out
      _buildSwapCalldata(address(tokenB), address(tokenA), 0)
    );

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.SlippageExceeded.selector, 0));
    gateway.withdrawAndSwap(params);
  }

  // ==================== WithdrawAndSwap: Insufficient shares ====================

  function test_withdrawAndSwap_fail_no_shares() public {
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](0);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: 100e18,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(); // transferFrom will fail (no allowance / balance)
    gateway.withdrawAndSwap(params);
  }

  // ==================== WithdrawAndSwap: Paused ====================

  function test_withdrawAndSwap_fail_when_paused() public {
    uint256 shares = _depositForAlice();
    gateway.setPaused(true);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert();
    gateway.withdrawAndSwap(params);
  }

  // ==================== Sweep: Extra sweep tokens ====================

  function test_swapAndDeposit_sweep_intermediary_token() public {
    // Alice has tokenX and swaps only part of it. Extra tokenX should be returned.
    tokenX.mint(ALICE, 200e18);
    _approveGatewayAll(ALICE);

    tokenA.mint(address(router), 100e18);
    router.setRate(address(tokenX), address(tokenA), 1, 1);

    // Only swap 50X → 50A, but pulled 200X
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      200e18,
      address(tokenA),
      0,
      _buildSwapCalldata(address(tokenX), address(tokenA), 50e18) // only swaps 50
    );

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenX);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

    // This will revert because we don't have enough for all 4 vault tokens,
    // but the sweep logic is what we're testing.
    // Instead, let's also fund the other 3 tokens
    tokenB.mint(ALICE, 100e18);
    tokenC.mint(ALICE, 25e6);
    tokenD.mint(ALICE, 50e18);

    // Rebuild swaps
    SharedVaultGateway.SwapParams[] memory swaps2 = new SharedVaultGateway.SwapParams[](5);
    swaps2[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      200e18,
      address(tokenA),
      0,
      _buildSwapCalldata(address(tokenX), address(tokenA), 50e18)
    );
    swaps2[1] = SharedVaultGateway.SwapParams(address(tokenA), 0, address(tokenA), 0, ""); // no-op, A already in
    swaps2[2] = SharedVaultGateway.SwapParams(address(tokenB), 100e18, address(tokenB), 0, "");
    swaps2[3] = SharedVaultGateway.SwapParams(address(tokenC), 25e6, address(tokenC), 0, "");
    swaps2[4] = SharedVaultGateway.SwapParams(address(tokenD), 50e18, address(tokenD), 0, "");

    params.swaps = swaps2;

    vm.prank(ALICE);
    gateway.swapAndDeposit(params);

    // Leftover tokenX should be returned to Alice (200 - 50 = 150)
    assertEq(tokenX.balanceOf(ALICE), 150e18, "Leftover tokenX returned to Alice");
    assertEq(tokenX.balanceOf(address(gateway)), 0, "No tokenX in gateway");
  }

  // ==================== Gateway is stateless after operations ====================

  function test_gateway_stateless_after_deposit() public {
    _depositForAlice();

    // After deposit, gateway should hold zero of everything
    assertEq(tokenA.balanceOf(address(gateway)), 0);
    assertEq(tokenB.balanceOf(address(gateway)), 0);
    assertEq(tokenC.balanceOf(address(gateway)), 0);
    assertEq(tokenD.balanceOf(address(gateway)), 0);
    assertEq(vault.balanceOf(address(gateway)), 0);
    assertEq(address(gateway).balance, 0);
  }

  function test_gateway_stateless_after_withdraw() public {
    uint256 shares = _depositForAlice();

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    assertEq(tokenA.balanceOf(address(gateway)), 0);
    assertEq(tokenB.balanceOf(address(gateway)), 0);
    assertEq(tokenC.balanceOf(address(gateway)), 0);
    assertEq(tokenD.balanceOf(address(gateway)), 0);
    assertEq(vault.balanceOf(address(gateway)), 0);
    assertEq(address(gateway).balance, 0);
  }

  // ==================== Multiple users can use gateway ====================

  function test_multiple_users_deposit_withdraw() public {
    // Alice deposits
    uint256 aliceShares = _depositForAlice();
    assertGt(aliceShares, 0);

    // Bob deposits the same proportional amounts
    tokenA.mint(BOB, 100e18);
    tokenB.mint(BOB, 200e18);
    tokenC.mint(BOB, 50e6);
    tokenD.mint(BOB, 100e18);

    vm.startPrank(BOB);
    GatewayMockERC20(address(tokenA)).approve(address(gateway), type(uint256).max);
    GatewayMockERC20(address(tokenB)).approve(address(gateway), type(uint256).max);
    GatewayMockERC20(address(tokenC)).approve(address(gateway), type(uint256).max);
    GatewayMockERC20(address(tokenD)).approve(address(gateway), type(uint256).max);
    GatewayMockERC20(address(vault)).approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps[1] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory depositParams = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(BOB);
    uint256 bobShares = gateway.swapAndDeposit(depositParams);
    assertGt(bobShares, 0);

    // Both withdraw
    SharedVaultGateway.WithdrawAndSwapParams memory withdrawParams = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: aliceShares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(withdrawParams);

    withdrawParams.shares = bobShares;
    vm.prank(BOB);
    gateway.withdrawAndSwap(withdrawParams);

    // Both have tokens, gateway is clean
    assertGt(tokenA.balanceOf(ALICE), 0);
    assertGt(tokenA.balanceOf(BOB), 0);
    assertEq(tokenA.balanceOf(address(gateway)), 0);
    assertEq(vault.balanceOf(address(gateway)), 0);
  }

  // ==================== amountIn=0 uses full balance ====================

  function test_swap_amountIn_zero_uses_full_balance() public {
    // Fund router
    tokenB.mint(address(router), 200e18);
    router.setRate(address(tokenA), address(tokenB), 2, 1); // 1A → 2B

    tokenA.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // Pull 100A, then swap with amountIn=0 (should use full 100A balance)
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    // Pull tokenA first
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    // Swap full balance of tokenA → tokenB
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenA),
      0,
      address(tokenB),
      100e18,
      _buildSwapCalldata(address(tokenA), address(tokenB), 100e18)
    );

    // This won't successfully deposit (only has B, not A/C/D), but we can verify the swap works
    // by catching the revert from vault and checking balances before sweep
    // For a cleaner test, let's fund other tokens too
    tokenA.mint(ALICE, 50e18); // will be deposited as tokenA
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);

    SharedVaultGateway.SwapParams[] memory swaps2 = new SharedVaultGateway.SwapParams[](5);
    swaps2[0] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps2[1] = SharedVaultGateway.SwapParams(
      address(tokenA),
      0,
      address(tokenB),
      100e18,
      _buildSwapCalldata(address(tokenA), address(tokenB), 100e18)
    );
    swaps2[2] = SharedVaultGateway.SwapParams(address(tokenA), 50e18, address(tokenA), 0, "");
    swaps2[3] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps2[4] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps2,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);
    assertGt(shares, 0, "Deposit succeeded after swap with amountIn=0");
  }

  // ==================== 2-token vault (simpler case) ====================

  function test_swapAndDeposit_two_token_vault() public {
    // Create a simpler 2-token vault
    SharedVault vault2 = new SharedVault();
    GatewayMockERC20 tA = new GatewayMockERC20("TA", "TA", 18);
    GatewayMockERC20 tB = new GatewayMockERC20("TB", "TB", 18);

    tA.mint(address(this), 100e18);
    tB.mint(address(this), 200e18);
    tA.transfer(address(vault2), 100e18);
    tB.transfer(address(vault2), 200e18);

    address[4] memory v2Tokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    vault2.initialize("Two Token", v2Tokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0));

    // Alice deposits a single token (tokenX) and swaps to A and B
    tA.mint(address(router), 50e18);
    tB.mint(address(router), 100e18);
    router.setRate(address(tokenX), address(tA), 1, 2); // 2X → 1A
    router.setRate(address(tokenX), address(tB), 1, 1); // 1X → 1B

    tokenX.mint(ALICE, 200e18);
    vm.prank(ALICE);
    GatewayMockERC20(address(tokenX)).approve(address(gateway), type(uint256).max);
    vm.prank(ALICE);
    GatewayMockERC20(address(vault2)).approve(address(gateway), type(uint256).max);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tA),
      40e18,
      _buildSwapCalldata(address(tokenX), address(tA), 100e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tB),
      90e18,
      _buildSwapCalldata(address(tokenX), address(tB), 100e18)
    );

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenX);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault2)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "Got shares from 2-token vault");
    assertEq(vault2.balanceOf(ALICE), shares);
    assertEq(tokenX.balanceOf(address(gateway)), 0, "No leftover tokenX");
    assertEq(tA.balanceOf(address(gateway)), 0, "No leftover tA");
    assertEq(tB.balanceOf(address(gateway)), 0, "No leftover tB");
  }

  // ==================== Full round-trip: deposit + withdraw ====================

  function test_full_round_trip_swap_deposit_withdraw_swap() public {
    // Alice: tokenX → swaps → 4 vault tokens → deposit → shares
    // then:  shares → withdraw → 4 vault tokens → swaps → tokenX

    tokenA.mint(address(router), 200e18);
    tokenB.mint(address(router), 400e18);
    tokenC.mint(address(router), 100e6);
    tokenD.mint(address(router), 200e18);
    tokenX.mint(address(router), 2000e18);

    router.setRate(address(tokenX), address(tokenA), 1, 1);
    router.setRate(address(tokenX), address(tokenB), 2, 1);
    router.setRate(address(tokenX), address(tokenC), 50e6, 100e18);
    router.setRate(address(tokenX), address(tokenD), 1, 1);
    router.setRate(address(tokenA), address(tokenX), 1, 1);
    router.setRate(address(tokenB), address(tokenX), 1, 2);
    router.setRate(address(tokenC), address(tokenX), 100e18, 50e6);
    router.setRate(address(tokenD), address(tokenX), 1, 1);

    tokenX.mint(ALICE, 400e18);
    _approveGatewayAll(ALICE);

    // Deposit: 400X → 100A + 200B + 50C + 100D → vault shares
    SharedVaultGateway.SwapParams[] memory depositSwaps = new SharedVaultGateway.SwapParams[](4);
    depositSwaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenA),
      90e18,
      _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );
    depositSwaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenB),
      180e18,
      _buildSwapCalldata(address(tokenX), address(tokenB), 100e18)
    );
    depositSwaps[2] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenC),
      45e6,
      _buildSwapCalldata(address(tokenX), address(tokenC), 100e18)
    );
    depositSwaps[3] = SharedVaultGateway.SwapParams(
      address(tokenX),
      100e18,
      address(tokenD),
      90e18,
      _buildSwapCalldata(address(tokenX), address(tokenD), 100e18)
    );

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenX);

    SharedVaultGateway.SwapAndDepositParams memory depositParams = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: depositSwaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(depositParams);
    assertGt(shares, 0, "Got shares");
    uint256 xAfterDeposit = tokenX.balanceOf(ALICE);

    // Withdraw: shares → 4 vault tokens → swaps → tokenX
    SharedVaultGateway.SwapParams[] memory withdrawSwaps = new SharedVaultGateway.SwapParams[](4);
    withdrawSwaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      0,
      address(tokenX),
      0,
      _buildSwapAllCalldata(address(tokenA), address(tokenX))
    );
    withdrawSwaps[1] = SharedVaultGateway.SwapParams(
      address(tokenB),
      0,
      address(tokenX),
      0,
      _buildSwapAllCalldata(address(tokenB), address(tokenX))
    );
    withdrawSwaps[2] = SharedVaultGateway.SwapParams(
      address(tokenC),
      0,
      address(tokenX),
      0,
      _buildSwapAllCalldata(address(tokenC), address(tokenX))
    );
    withdrawSwaps[3] = SharedVaultGateway.SwapParams(
      address(tokenD),
      0,
      address(tokenX),
      0,
      _buildSwapAllCalldata(address(tokenD), address(tokenX))
    );

    SharedVaultGateway.WithdrawAndSwapParams memory withdrawParams = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: withdrawSwaps,
      sweepTokens: sweepTokens
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(withdrawParams);

    uint256 xAfterWithdraw = tokenX.balanceOf(ALICE);
    assertGt(xAfterWithdraw, xAfterDeposit, "Alice recovered tokenX from round-trip");

    // Gateway clean
    assertEq(tokenA.balanceOf(address(gateway)), 0);
    assertEq(tokenB.balanceOf(address(gateway)), 0);
    assertEq(tokenC.balanceOf(address(gateway)), 0);
    assertEq(tokenD.balanceOf(address(gateway)), 0);
    assertEq(tokenX.balanceOf(address(gateway)), 0);
    assertEq(vault.balanceOf(address(gateway)), 0);
  }

  /// @notice Native ETH (`tokenIn == address(0)`) and WETH ERC20 (`tokenIn == weth`) are independent:
  ///         only `address(0)` entries consume `msg.value`; WETH is always `transferFrom`.
  function test_swapAndDeposit_native_eth_and_weth_erc20_together() public {
    vm.deal(ALICE, 6 ether);
    vm.startPrank(ALICE);
    mockWeth.deposit{ value: 5 ether }();
    mockWeth.approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](6);
    swaps[0] = SharedVaultGateway.SwapParams(address(mockWeth), 5 ether, address(mockWeth), 0, "");
    swaps[1] = SharedVaultGateway.SwapParams(address(0), 1 ether, address(0), 0, "");
    swaps[2] = SharedVaultGateway.SwapParams(address(tokenA), 100e18, address(tokenA), 0, "");
    swaps[3] = SharedVaultGateway.SwapParams(address(tokenB), 200e18, address(tokenB), 0, "");
    swaps[4] = SharedVaultGateway.SwapParams(address(tokenC), 50e6, address(tokenC), 0, "");
    swaps[5] = SharedVaultGateway.SwapParams(address(tokenD), 100e18, address(tokenD), 0, "");

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(mockWeth);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit{ value: 1 ether }(params);

    assertGt(shares, 0);
    assertEq(vault.balanceOf(ALICE), shares);
    assertEq(mockWeth.balanceOf(ALICE), 6 ether, "unused WETH swept back");
    assertEq(ALICE.balance, 0, "no stranded ETH on user after sweep");
    assertEq(mockWeth.balanceOf(address(gateway)), 0);
  }

  function test_swapAndDeposit_fail_insufficient_msg_value() public {
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(address(0), 2 ether, address(0), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.deal(ALICE, 1 ether);
    vm.prank(ALICE);
    vm.expectRevert(SharedVaultGateway.InsufficientMsgValue.selector);
    gateway.swapAndDeposit{ value: 1 ether }(params);
  }

  function test_swapAndDeposit_fail_insufficient_post_swap_balance() public {
    tokenA.mint(ALICE, 1e18);
    vm.prank(ALICE);
    GatewayMockERC20(address(tokenA)).approve(address(gateway), type(uint256).max);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 1e18, address(tokenA), 0, "");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      swaps: swaps,
      minDepositAmounts: [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientPostSwapBalance.selector, 0));
    gateway.swapAndDeposit(params);
  }
}
