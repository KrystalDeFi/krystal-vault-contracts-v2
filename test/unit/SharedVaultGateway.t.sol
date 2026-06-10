// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultGateway } from "../../contracts/shared-vault/core/SharedVaultGateway.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { Withdrawable } from "../../contracts/common/Withdrawable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

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
    (bool ok,) = msg.sender.call{ value: wad }("");
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

contract GatewayFotToken {
  string public name = "Gateway FOT";
  string public symbol = "GFOT";
  uint8 public decimals = 18;
  uint256 public immutable feeBps;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  constructor(uint256 _feeBps) {
    feeBps = _feeBps;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    _transfer(from, to, amount);
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function _transfer(address from, address to, uint256 amount) internal {
    require(balanceOf[from] >= amount, "Insufficient balance");
    uint256 fee = (amount * feeBps) / 10_000;
    balanceOf[from] -= amount;
    balanceOf[to] += amount - fee;
    totalSupply -= fee;
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
    if (r.rateDen > 0) amountOut = (amountIn * r.rateNum) / r.rateDen;
    else amountOut = amountIn; // default 1:1
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
    if (r.rateDen > 0) amountOut = (amountIn * r.rateNum) / r.rateDen;
    else amountOut = amountIn;
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
    configManager.initialize(address(this), targets, callers, address(this), 0, new address[](0), new address[](0), new address[](0));

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
      "4-Token Vault", vaultTokens, initialAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );
  }

  // ==================== Helpers ====================

  function _buildSwapCalldata(address tokenIn, address tokenOut, uint256 amountIn)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodeCall(MockAggregatorRouter.swap, (tokenIn, tokenOut, amountIn));
  }

  function _buildSwapAllCalldata(address tokenIn, address tokenOut) internal pure returns (bytes memory) {
    return abi.encodeCall(MockAggregatorRouter.swapAll, (tokenIn, tokenOut));
  }

  function _sweepTokensArray(address token) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = token;
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

  // ==================== Inputs Builders ====================

  function _inputs1(address t0, uint256 a0) internal pure returns (SharedVaultGateway.InputToken[] memory inputs) {
    inputs = new SharedVaultGateway.InputToken[](1);
    inputs[0] = SharedVaultGateway.InputToken(t0, a0);
  }

  function _inputs2(address t0, uint256 a0, address t1, uint256 a1)
    internal
    pure
    returns (SharedVaultGateway.InputToken[] memory inputs)
  {
    inputs = new SharedVaultGateway.InputToken[](2);
    inputs[0] = SharedVaultGateway.InputToken(t0, a0);
    inputs[1] = SharedVaultGateway.InputToken(t1, a1);
  }

  function _inputs3(address t0, uint256 a0, address t1, uint256 a1, address t2, uint256 a2)
    internal
    pure
    returns (SharedVaultGateway.InputToken[] memory inputs)
  {
    inputs = new SharedVaultGateway.InputToken[](3);
    inputs[0] = SharedVaultGateway.InputToken(t0, a0);
    inputs[1] = SharedVaultGateway.InputToken(t1, a1);
    inputs[2] = SharedVaultGateway.InputToken(t2, a2);
  }

  function _inputs4(address t0, uint256 a0, address t1, uint256 a1, address t2, uint256 a2, address t3, uint256 a3)
    internal
    pure
    returns (SharedVaultGateway.InputToken[] memory inputs)
  {
    inputs = new SharedVaultGateway.InputToken[](4);
    inputs[0] = SharedVaultGateway.InputToken(t0, a0);
    inputs[1] = SharedVaultGateway.InputToken(t1, a1);
    inputs[2] = SharedVaultGateway.InputToken(t2, a2);
    inputs[3] = SharedVaultGateway.InputToken(t3, a3);
  }

  function _emptyInputs() internal pure returns (SharedVaultGateway.InputToken[] memory) {
    return new SharedVaultGateway.InputToken[](0);
  }

  // Review fix: a swap whose tokenIn == tokenOut is a no-op self-swap. The gateway must reject it
  // explicitly rather than letting it surface as an opaque balance-delta underflow.
  function test_swapAndDeposit_revertsOnIdenticalSwapTokens() public {
    GatewayMockERC20(address(tokenA)).mint(ALICE, 10e18);
    _approveGateway(address(tokenA), ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams({
      tokenIn: address(tokenA),
      amountIn: 1e18,
      tokenOut: address(tokenA), // identical in/out
      amountOutMin: 0,
      swapData: _buildSwapCalldata(address(tokenA), address(tokenA), 1e18)
    });

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(tokenA), 1e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: _sweepTokensArray(address(tokenA))
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.IdenticalSwapTokens.selector, 0));
    gateway.swapAndDeposit(params);
  }

  function test_swapAndDeposit_revertsWhenSwapBatchExceedsPracticalBound() public {
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](gateway.MAX_SWAPS() + 1);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: new SharedVaultGateway.InputToken[](0),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.TooManySwaps.selector, swaps.length));
    gateway.swapAndDeposit(params);
  }

  function test_withdrawAndSwap_revertsWhenSwapBatchExceedsPracticalBound() public {
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](gateway.MAX_SWAPS() + 1);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: 0,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.TooManySwaps.selector, swaps.length));
    gateway.withdrawAndSwap(params);
  }

  // ==================== minShares / slippageBps forwarding ====================

  /// @dev `minShares` is the gateway's only share-price sandwich guard (the struct doc says so) — it
  ///      must be forwarded verbatim to vault.deposit and a sub-minimum mint must revert the WHOLE
  ///      gateway call (no partial deposit, no swallowed shortfall).
  function test_swapAndDeposit_forwardsMinShares_revertsBelowMinimum() public {
    GatewayMockERC20(address(tokenA)).mint(ALICE, 10e18);
    GatewayMockERC20(address(tokenB)).mint(ALICE, 20e18);
    GatewayMockERC20(address(tokenC)).mint(ALICE, 5e6);
    GatewayMockERC20(address(tokenD)).mint(ALICE, 10e18);
    _approveGatewayAll(ALICE);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(5e6), uint256(10e18)];
    uint256 preview = vault.previewDeposit(amounts);
    assertGt(preview, 0, "sanity: proportional deposit previews shares");

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(address(tokenA), 10e18, address(tokenB), 20e18, address(tokenC), 5e6, address(tokenD), 10e18),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: preview + 1, // one share above what the deposit can mint
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(ISharedCommon.InsufficientShares.selector);
    gateway.swapAndDeposit(params);
  }

  /// @dev Boundary: minShares == actual minted shares passes, and the caller receives exactly them.
  function test_swapAndDeposit_forwardsMinShares_succeedsAtBoundary() public {
    GatewayMockERC20(address(tokenA)).mint(ALICE, 10e18);
    GatewayMockERC20(address(tokenB)).mint(ALICE, 20e18);
    GatewayMockERC20(address(tokenC)).mint(ALICE, 5e6);
    GatewayMockERC20(address(tokenD)).mint(ALICE, 10e18);
    _approveGatewayAll(ALICE);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(5e6), uint256(10e18)];
    uint256 preview = vault.previewDeposit(amounts);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(address(tokenA), 10e18, address(tokenB), 20e18, address(tokenC), 5e6, address(tokenD), 10e18),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: preview,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertEq(shares, preview, "minted exactly the previewed shares");
    assertEq(vault.balanceOf(ALICE), preview, "shares attributed to the gateway caller");
  }

  /// @dev `slippageBps` must be forwarded verbatim to vault.deposit: a value above the vault's
  ///      10_000 cap reverts there with InvalidAmount, proving the parameter is not dropped.
  function test_swapAndDeposit_forwardsSlippageBps_vaultValidatesCap() public {
    GatewayMockERC20(address(tokenA)).mint(ALICE, 10e18);
    GatewayMockERC20(address(tokenB)).mint(ALICE, 20e18);
    GatewayMockERC20(address(tokenC)).mint(ALICE, 5e6);
    GatewayMockERC20(address(tokenD)).mint(ALICE, 10e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(address(tokenA), 10e18, address(tokenB), 20e18, address(tokenC), 5e6, address(tokenD), 10e18),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 10_001, // above the vault's cap
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    gateway.swapAndDeposit(params);
  }

  function _setupEightDecimalGatewayVault() internal returns (SharedVault v, GatewayMockERC20 tA, GatewayMockERC20 tB) {
    v = new SharedVault();
    tA = new GatewayMockERC20("Gateway Eight A", "GEA", 18);
    tB = new GatewayMockERC20("Gateway Eight B", "GEB", 8);

    tA.mint(address(v), 100e18);
    tB.mint(address(v), 5521);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(5521), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize(
      "Gateway Eight Decimal Vault",
      vtokens,
      initAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(0),
      0
    );
  }

  function _setupZeroBalanceSlotGatewayVault()
    internal
    returns (SharedVault v, GatewayMockERC20 tA, GatewayMockERC20 tB, GatewayMockERC20 tC)
  {
    v = new SharedVault();
    tA = new GatewayMockERC20("Gateway Zero A", "GZA", 18);
    tB = new GatewayMockERC20("Gateway Zero B", "GZB", 6);
    tC = new GatewayMockERC20("Gateway Zero C", "GZC", 18);

    tA.mint(address(v), 1e15);
    tB.mint(address(v), 840_707);

    address[4] memory vtokens = [address(tA), address(tB), address(tC), address(0)];
    uint256[4] memory initAmounts = [uint256(1e15), uint256(840_707), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize(
      "Gateway Zero Slot Vault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );
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

  function test_setPaused_fail_unauthorized() public {
    vm.prank(ALICE);
    vm.expectRevert();
    gateway.setPaused(true);
  }

  /// @dev The event carries the OLD router (indexed) so off-chain monitors can detect router rotation.
  function test_setSwapRouter_emitsSwapRouterUpdated() public {
    address newRouter = address(0xBEEF);
    vm.expectEmit(true, true, false, true, address(gateway));
    emit SharedVaultGateway.SwapRouterUpdated(address(router), newRouter);
    gateway.setSwapRouter(newRouter);
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

    // Pull all 4 tokens directly via inputs[]; no swaps needed.
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 100e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: new SharedVaultGateway.SwapParams[](0),
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

  function test_swapAndDeposit_feeOnTransferVaultToken_usesActualGatewayBalanceAndSweepsClean() public {
    GatewayFotToken fot = new GatewayFotToken(200);
    GatewayMockERC20 paired = new GatewayMockERC20("Paired", "PAIR", 18);
    SharedVault fotVault = new SharedVault();

    fot.mint(address(this), 100e18);
    paired.mint(address(this), 100e18);
    fot.transfer(address(fotVault), 100e18); // vault receives 98e18
    paired.transfer(address(fotVault), 100e18);

    address[4] memory vaultTokens = [address(fot), address(paired), address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    fotVault.initialize(
      "Gateway FOT Vault", vaultTokens, initialAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );

    fot.mint(ALICE, 50e18);
    paired.mint(ALICE, 50e18);

    vm.startPrank(ALICE);
    fot.approve(address(gateway), type(uint256).max);
    paired.approve(address(gateway), type(uint256).max);

    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](2);
    inputs[0] = SharedVaultGateway.InputToken({ token: address(fot), amount: 50e18 });
    inputs[1] = SharedVaultGateway.InputToken({ token: address(paired), amount: 50e18 });

    address[] memory sweepTokens = new address[](2);
    sweepTokens[0] = address(fot);
    sweepTokens[1] = address(paired);

    uint256 fotVaultBefore = fot.balanceOf(address(fotVault));
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(fotVault)),
      inputs: inputs,
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

    uint256 shares = gateway.swapAndDeposit(params);
    vm.stopPrank();

    assertGt(shares, 0, "FOT gateway deposit mints shares from actual receipt");
    assertEq(fotVault.balanceOf(ALICE), shares, "shares are attributed to caller");
    assertEq(
      fot.balanceOf(address(fotVault)) - fotVaultBefore,
      (49e18 * 9800) / 10_000,
      "vault credits actual second-hop FOT receipt"
    );
    assertEq(fot.balanceOf(address(gateway)), 0, "no FOT stranded in gateway");
    assertEq(paired.balanceOf(address(gateway)), 0, "no paired token stranded in gateway");
  }

  function test_swapAndDeposit_emitsVaultDepositForShareholder() public {
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 100e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    uint256[4] memory expectedAmounts = [uint256(100e18), uint256(200e18), uint256(50e6), uint256(100e18)];
    uint256 expectedShares = vault.previewDeposit(expectedAmounts);

    vm.expectEmit(true, true, false, true, address(vault));
    emit ISharedVault.VaultDeposit(VAULT_OWNER, ALICE, expectedAmounts, expectedShares);

    vm.prank(ALICE);
    gateway.swapAndDeposit(params);

    assertEq(vault.balanceOf(ALICE), expectedShares, "Alice receives shares directly");
    assertEq(vault.balanceOf(address(gateway)), 0, "Gateway never holds minted shares");
  }

  /// @notice The GATEWAY's own SwapAndDeposit event (not the vault's VaultDeposit) is the integration
  ///         signal off-chain indexers key on; it must carry the vault, the depositor, and the minted shares.
  function test_swapAndDeposit_emitsGatewaySwapAndDepositEvent() public {
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 100e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    uint256[4] memory expectedAmounts = [uint256(100e18), uint256(200e18), uint256(50e6), uint256(100e18)];
    uint256 expectedShares = vault.previewDeposit(expectedAmounts);

    vm.expectEmit(true, true, false, true, address(gateway));
    emit SharedVaultGateway.SwapAndDeposit(address(vault), ALICE, expectedShares);

    vm.prank(ALICE);
    gateway.swapAndDeposit(params);
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
      address(tokenX), 100e18, address(tokenA), 90e18, _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tokenB), 180e18, _buildSwapCalldata(address(tokenX), address(tokenB), 100e18)
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tokenC), 45e6, _buildSwapCalldata(address(tokenX), address(tokenC), 100e18)
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tokenD), 90e18, _buildSwapCalldata(address(tokenX), address(tokenD), 100e18)
    );

    // Single tokenX input of 400, split internally across 4 swaps.
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(tokenX), 400e18),
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

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 150e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: new SharedVaultGateway.SwapParams[](0),
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

    // Pull 200A (100 will be swapped to C, 100 deposited directly), 200B, 100D.
    // Then swap 100A → 50C from gateway balance.
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA), 100e18, address(tokenC), 45e6, _buildSwapCalldata(address(tokenA), address(tokenC), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenA), 200e18, address(tokenB), 200e18, address(tokenD), 100e18),
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
      address(tokenX), 100e18, address(tokenA), 90e18, _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(tokenX), 100e18),
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
      address(tokenX), 100e18, address(tokenA), 0, _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(tokenX), 100e18),
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

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _emptyInputs(),
      swaps: new SharedVaultGateway.SwapParams[](0),
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

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 100e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: new SharedVaultGateway.SwapParams[](0),
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

  function test_withdrawAndSwap_emitsVaultWithdrawForShareholder() public {
    uint256 shares = _depositForAlice();

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    uint256[4] memory expectedAmounts = vault.previewWithdraw(shares);

    vm.expectEmit(true, true, true, true, address(vault));
    emit ISharedVault.VaultWithdraw(VAULT_OWNER, ALICE, expectedAmounts, shares);

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    assertEq(vault.balanceOf(ALICE), 0, "Alice shares burned");
    assertEq(vault.balanceOf(address(gateway)), 0, "Gateway never holds burned shares");
  }

  /// @notice The GATEWAY's own WithdrawAndSwap event must carry the vault, the withdrawer, and the
  ///         exact share count burned (the caller-supplied `params.shares`, not a derived value).
  function test_withdrawAndSwap_emitsGatewayWithdrawAndSwapEvent() public {
    uint256 shares = _depositForAlice();

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.expectEmit(true, true, false, true, address(gateway));
    emit SharedVaultGateway.WithdrawAndSwap(address(vault), ALICE, shares);

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);
  }

  function test_withdrawAndSwap_doesNotSweepPreExistingNativeBalance() public {
    uint256 shares = _depositForAlice();
    vm.deal(address(gateway), 1 ether);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    uint256 aliceEthBefore = ALICE.balance;

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    assertEq(ALICE.balance, aliceEthBefore, "pre-existing ETH not sent to caller");
    assertEq(address(gateway).balance, 1 ether, "pre-existing ETH remains recoverable by owner");
  }

  function test_withdrawAndSwap_doesNotSweepPreExistingErc20Balance() public {
    uint256 shares = _depositForAlice();
    uint256[4] memory expectedAmounts = vault.previewWithdraw(shares);
    uint256 preExistingTokenA = 5e18;
    tokenA.mint(address(gateway), preExistingTokenA);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    uint256 aliceTokenABefore = tokenA.balanceOf(ALICE);

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    assertEq(tokenA.balanceOf(ALICE), aliceTokenABefore + expectedAmounts[0], "caller receives only call delta");
    assertEq(tokenA.balanceOf(address(gateway)), preExistingTokenA, "pre-existing token remains recoverable by owner");
  }

  function test_withdrawAndSwap_fullBalanceSwapDoesNotConsumePreExistingInputBalance() public {
    uint256 shares = _depositForAlice();
    uint256[4] memory expectedAmounts = vault.previewWithdraw(shares);
    uint256 preExistingTokenB = 5e18;
    tokenB.mint(address(gateway), preExistingTokenB);
    tokenA.mint(address(router), 1000e18);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenB), 0, address(tokenA), 0, _buildSwapAllCalldata(address(tokenB), address(tokenA))
    );

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: new address[](0)
    });

    uint256 aliceTokenABefore = tokenA.balanceOf(ALICE);

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    assertEq(
      tokenA.balanceOf(ALICE),
      aliceTokenABefore + expectedAmounts[0] + expectedAmounts[1],
      "caller receives direct tokenA and swapped per-call tokenB only"
    );
    assertEq(tokenB.balanceOf(address(gateway)), preExistingTokenB, "pre-existing input token remains untouched");
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
      address(tokenB), 0, address(tokenA), 0, _buildSwapAllCalldata(address(tokenB), address(tokenA))
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenC), 0, address(tokenA), 0, _buildSwapAllCalldata(address(tokenC), address(tokenA))
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(tokenD), 0, address(tokenA), 0, _buildSwapAllCalldata(address(tokenD), address(tokenA))
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
    tokenB.mint(ALICE, 100e18);
    tokenC.mint(ALICE, 25e6);
    tokenD.mint(ALICE, 50e18);
    _approveGatewayAll(ALICE);

    tokenA.mint(address(router), 100e18);
    router.setRate(address(tokenX), address(tokenA), 1, 1);

    // Pull 200X total but only swap 50X → tokenA; 150X remains and is swept back.
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX), 50e18, address(tokenA), 0, _buildSwapCalldata(address(tokenX), address(tokenA), 50e18)
    );

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenX);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(address(tokenX), 200e18, address(tokenB), 100e18, address(tokenC), 25e6, address(tokenD), 50e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

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

    SharedVaultGateway.SwapAndDepositParams memory depositParams = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 100e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: new SharedVaultGateway.SwapParams[](0),
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
    // Fund router; rate 1A → 2B
    tokenB.mint(address(router), 200e18);
    router.setRate(address(tokenA), address(tokenB), 2, 1);

    // Alice provides 150A, 50C, 100D directly. The swap consumes full A balance
    // (amountIn=0); router's swapData hardcodes 100A → 200B. After swap: 50A left.
    tokenA.mint(ALICE, 150e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      0, // amountIn=0 → use full gateway balance for approval sizing
      address(tokenB),
      100e18,
      _buildSwapCalldata(address(tokenA), address(tokenB), 100e18) // router pulls only 100A
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenA), 150e18, address(tokenC), 50e6, address(tokenD), 100e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);
    assertGt(shares, 0, "Deposit succeeded after swap with amountIn=0");
  }

  function test_swap_residual_allowance_reset_after_partial_fill() public {
    // Partial-fill scenario: router is approved for 150A but only consumes 100A.
    // The post-call safeApprove(0) must zero out the leftover 50A allowance so the
    // router cannot drain vault tokens in a future transaction.
    // Vault ratio: 1000A:2000B:500C:1000D. Alice supplies A/C/D, swaps 100A→200B.
    // After swap gateway holds 50A+200B+50C+100D — binding is A (50/1000=5%).
    tokenB.mint(address(router), 200e18);
    router.setRate(address(tokenA), address(tokenB), 2, 1);

    tokenA.mint(ALICE, 150e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // Swap amountIn=150A but calldata only asks the router to pull 100A (partial fill).
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA), 150e18, address(tokenB), 0, _buildSwapCalldata(address(tokenA), address(tokenB), 100e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenA), 150e18, address(tokenC), 50e6, address(tokenD), 100e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    gateway.swapAndDeposit(params);

    assertEq(tokenA.allowance(address(gateway), address(router)), 0, "residual allowance must be reset to 0");
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
    vault2.initialize(
      "Two Token", v2Tokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );

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
      address(tokenX), 100e18, address(tA), 40e18, _buildSwapCalldata(address(tokenX), address(tA), 100e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tB), 90e18, _buildSwapCalldata(address(tokenX), address(tB), 100e18)
    );

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenX);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault2)),
      inputs: _inputs1(address(tokenX), 200e18),
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

  // ==================== minTokenPrecision: Gateway → Vault ====================

  function test_swapAndDeposit_directDeposit_belowVaultPrecisionFloorRevertsFromVault() public {
    (SharedVault dustVault, GatewayMockERC20 tA, GatewayMockERC20 tB) = _setupEightDecimalGatewayVault();

    tA.mint(ALICE, 10e18);
    tB.mint(ALICE, 999);
    vm.startPrank(ALICE);
    tA.approve(address(gateway), type(uint256).max);
    tB.approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(dustVault)),
      inputs: _inputs2(address(tA), 10e18, address(tB), 999),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(999), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    gateway.swapAndDeposit(params);
  }

  function test_swapAndDeposit_directDeposit_usesVaultPrecisionFloor() public {
    (SharedVault dustVault, GatewayMockERC20 tA, GatewayMockERC20 tB) = _setupEightDecimalGatewayVault();

    uint256[4] memory vaultMins = dustVault.getMinDepositAmounts();
    assertEq(vaultMins[1], 1000, "8-decimal vault floor");

    tA.mint(ALICE, 10e18);
    tB.mint(ALICE, 1000);
    vm.startPrank(ALICE);
    tA.approve(address(gateway), type(uint256).max);
    tB.approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(dustVault)),
      inputs: _inputs2(address(tA), 10e18, address(tB), 1000),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: vaultMins,
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "shares minted");
    assertEq(dustVault.balanceOf(ALICE), shares, "gateway deposits to Alice");
    assertEq(tB.balanceOf(address(dustVault)), 6521, "vault received the 1_000-unit floor");
    assertEq(tA.balanceOf(address(gateway)), 0, "gateway has no tokenA residue");
    assertEq(tB.balanceOf(address(gateway)), 0, "gateway has no tokenB residue");
  }

  function test_swapAndDeposit_postSwapBelowVaultFloorRevertsAtGatewayMinCheck() public {
    (SharedVault dustVault, GatewayMockERC20 tA, GatewayMockERC20 tB) = _setupEightDecimalGatewayVault();

    tA.mint(address(router), 10e18);
    tB.mint(address(router), 999);
    router.setRate(address(tokenX), address(tA), 1, 1);
    router.setRate(address(tokenX), address(tB), 999, 1e18);

    tokenX.mint(ALICE, 11e18);
    vm.prank(ALICE);
    tokenX.approve(address(gateway), type(uint256).max);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX), 10e18, address(tA), 10e18, _buildSwapCalldata(address(tokenX), address(tA), 10e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX), 1e18, address(tB), 999, _buildSwapCalldata(address(tokenX), address(tB), 1e18)
    );

    uint256[4] memory vaultMins = dustVault.getMinDepositAmounts();
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(dustVault)),
      inputs: _inputs1(address(tokenX), 11e18),
      swaps: swaps,
      minDepositAmounts: vaultMins,
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientPostSwapBalance.selector, 1));
    gateway.swapAndDeposit(params);
  }

  function test_swapAndDeposit_swapOutputAtVaultFloorDeposits() public {
    (SharedVault dustVault, GatewayMockERC20 tA, GatewayMockERC20 tB) = _setupEightDecimalGatewayVault();

    tA.mint(address(router), 10e18);
    tB.mint(address(router), 1000);
    router.setRate(address(tokenX), address(tA), 1, 1);
    router.setRate(address(tokenX), address(tB), 1000, 1e18);

    tokenX.mint(ALICE, 11e18);
    vm.prank(ALICE);
    tokenX.approve(address(gateway), type(uint256).max);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX), 10e18, address(tA), 10e18, _buildSwapCalldata(address(tokenX), address(tA), 10e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX), 1e18, address(tB), 1000, _buildSwapCalldata(address(tokenX), address(tB), 1e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(dustVault)),
      inputs: _inputs1(address(tokenX), 11e18),
      swaps: swaps,
      minDepositAmounts: dustVault.getMinDepositAmounts(),
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "shares minted from swapped floor amount");
    assertEq(dustVault.balanceOf(ALICE), shares, "shares minted to Alice");
    assertEq(tB.balanceOf(address(dustVault)), 6521, "vault received 1_000 swapped units");
    assertEq(tokenX.balanceOf(address(gateway)), 0, "gateway has no tokenX residue");
  }

  function test_swapAndDeposit_returnsDustForConfiguredZeroBalanceSlot() public {
    (SharedVault zeroVault, GatewayMockERC20 tA, GatewayMockERC20 tB, GatewayMockERC20 tC) =
      _setupZeroBalanceSlotGatewayVault();

    tA.mint(address(router), 1e15);
    tB.mint(address(router), 840_707);
    router.setRate(address(tC), address(tA), 1, 1);
    router.setRate(address(tC), address(tB), 1, 1e9);

    uint256 inputAmount = 1_840_707_000_000_001;
    uint256 swapToA = 1e15;
    uint256 swapToB = 840_707_000_000_000;
    tC.mint(ALICE, inputAmount);
    vm.prank(ALICE);
    tC.approve(address(gateway), type(uint256).max);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tC), swapToA, address(tA), 1e15, _buildSwapCalldata(address(tC), address(tA), swapToA)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tC), swapToB, address(tB), 840_707, _buildSwapCalldata(address(tC), address(tB), swapToB)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(zeroVault)),
      inputs: _inputs1(address(tC), inputAmount),
      swaps: swaps,
      minDepositAmounts: [uint256(1e15), uint256(840_707), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "shares minted");
    assertEq(zeroVault.balanceOf(ALICE), shares, "shares minted to Alice");
    assertEq(tA.balanceOf(address(zeroVault)), 2e15, "tokenA deposited");
    assertEq(tB.balanceOf(address(zeroVault)), 1_681_414, "tokenB deposited");
    assertEq(tC.balanceOf(address(zeroVault)), 0, "zero-balance slot remains empty");
    assertEq(tC.balanceOf(ALICE), 1, "zero-ratio dust returned");
    assertEq(tC.balanceOf(address(gateway)), 0, "gateway has no tokenC residue");
  }

  /// @notice The revert arm of the zero-ratio-slot branch tested above: a live vault cannot accept
  ///         deposits into a configured slot whose current total balance is zero, so a nonzero
  ///         `minDepositAmounts` floor on that slot is unsatisfiable by construction and must revert
  ///         InsufficientPostSwapBalance(slot) instead of silently keeping the delta as sweepable dust.
  function test_swapAndDeposit_revertsWhenMinSetOnZeroRatioSlot() public {
    (SharedVault zeroVault, GatewayMockERC20 tA, GatewayMockERC20 tB, GatewayMockERC20 tC) =
      _setupZeroBalanceSlotGatewayVault();

    tA.mint(ALICE, 1e15);
    tB.mint(ALICE, 840_707);
    tC.mint(ALICE, 1_000);
    vm.startPrank(ALICE);
    tA.approve(address(gateway), type(uint256).max);
    tB.approve(address(gateway), type(uint256).max);
    tC.approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(zeroVault)),
      inputs: _inputs3(address(tA), 1e15, address(tB), 840_707, address(tC), 1_000),
      swaps: new SharedVaultGateway.SwapParams[](0),
      // Slot 2 (tC) has zero vault ratio — demanding a minimum there is unsatisfiable.
      minDepositAmounts: [uint256(0), uint256(0), uint256(1), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientPostSwapBalance.selector, 2));
    gateway.swapAndDeposit(params);
  }

  function test_withdrawAndSwap_forwardsBelowPrecisionFloorVaultDust() public {
    (SharedVault dustVault, GatewayMockERC20 tA, GatewayMockERC20 tB) = _setupEightDecimalGatewayVault();

    uint256 sharesToWithdraw = 1e18; // 10% of INITIAL_SHARES
    vm.prank(VAULT_OWNER);
    dustVault.transfer(ALICE, sharesToWithdraw);
    vm.prank(ALICE);
    dustVault.approve(address(gateway), type(uint256).max);

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(dustVault)),
      shares: sharesToWithdraw,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256[4] memory amounts = gateway.withdrawAndSwap(params);

    assertEq(amounts[0], 10e18, "10% tokenA withdrawn");
    assertEq(amounts[1], 552, "below-floor 8-decimal dust withdrawn");
    assertLt(amounts[1], dustVault.getMinDepositAmounts()[1], "withdraw output can be below deposit floor");
    assertEq(tA.balanceOf(ALICE), 10e18, "tokenA swept to Alice");
    assertEq(tB.balanceOf(ALICE), 552, "below-floor tokenB swept to Alice");
    assertEq(tA.balanceOf(address(gateway)), 0, "gateway has no tokenA residue");
    assertEq(tB.balanceOf(address(gateway)), 0, "gateway has no tokenB residue");
    assertEq(dustVault.balanceOf(address(gateway)), 0, "gateway has no share residue");
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
      address(tokenX), 100e18, address(tokenA), 90e18, _buildSwapCalldata(address(tokenX), address(tokenA), 100e18)
    );
    depositSwaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tokenB), 180e18, _buildSwapCalldata(address(tokenX), address(tokenB), 100e18)
    );
    depositSwaps[2] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tokenC), 45e6, _buildSwapCalldata(address(tokenX), address(tokenC), 100e18)
    );
    depositSwaps[3] = SharedVaultGateway.SwapParams(
      address(tokenX), 100e18, address(tokenD), 90e18, _buildSwapCalldata(address(tokenX), address(tokenD), 100e18)
    );

    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenX);

    SharedVaultGateway.SwapAndDepositParams memory depositParams = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(tokenX), 400e18),
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
      address(tokenA), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenA), address(tokenX))
    );
    withdrawSwaps[1] = SharedVaultGateway.SwapParams(
      address(tokenB), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenB), address(tokenX))
    );
    withdrawSwaps[2] = SharedVaultGateway.SwapParams(
      address(tokenC), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenC), address(tokenX))
    );
    withdrawSwaps[3] = SharedVaultGateway.SwapParams(
      address(tokenD), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenD), address(tokenX))
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

  // ==================== SwapAndDeposit: Native ETH via msg.value ====================

  /// @notice WETH ERC20 path (msg.value == 0): WETH is pulled from the user's wallet via transferFrom.
  ///         The two paths are mutually exclusive — WETH ERC20 and native ETH are not combined.
  function test_swapAndDeposit_weth_erc20_as_token_in() public {
    // Alice holds WETH as an ERC20; she wants to deposit to the vault using WETH as the swap input.
    // She converts 4 ETH to WETH: swap 0 pulls all 4 via transferFrom (amountIn=4e18), then each
    // subsequent swap with amountIn=0 draws 1 WETH from the progressively-decreasing gateway balance.
    vm.deal(ALICE, 4 ether);
    vm.startPrank(ALICE);
    mockWeth.deposit{ value: 4 ether }(); // convert 4 ETH → 4 WETH ERC20
    mockWeth.approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    tokenA.mint(address(router), 100e18);
    tokenB.mint(address(router), 200e18);
    tokenC.mint(address(router), 50e6);
    tokenD.mint(address(router), 100e18);
    router.setRate(address(mockWeth), address(tokenA), 100e18, 1 ether); // 1 WETH → 100 tokenA
    router.setRate(address(mockWeth), address(tokenB), 200e18, 1 ether); // 1 WETH → 200 tokenB
    router.setRate(address(mockWeth), address(tokenC), 50e6, 1 ether); // 1 WETH → 50e6 tokenC
    router.setRate(address(mockWeth), address(tokenD), 100e18, 1 ether); // 1 WETH → 100 tokenD

    _approveGatewayAll(ALICE);

    // inputs[] pulls all 4 WETH upfront. Each swap consumes 1 WETH from the gateway balance.
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      1 ether,
      address(tokenA),
      90e18,
      _buildSwapCalldata(address(mockWeth), address(tokenA), 1 ether)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      1 ether,
      address(tokenB),
      180e18,
      _buildSwapCalldata(address(mockWeth), address(tokenB), 1 ether)
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(mockWeth), 1 ether, address(tokenC), 45e6, _buildSwapCalldata(address(mockWeth), address(tokenC), 1 ether)
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      1 ether,
      address(tokenD),
      90e18,
      _buildSwapCalldata(address(mockWeth), address(tokenD), 1 ether)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(mockWeth), 4 ether),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params); // no msg.value — ERC20 WETH path

    assertGt(shares, 0, "shares received");
    assertEq(vault.balanceOf(ALICE), shares);
    assertEq(mockWeth.balanceOf(ALICE), 0, "all 4 WETH pulled from wallet and consumed");
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "no residual WETH in gateway");
    assertEq(address(gateway).balance, 0, "no ETH in gateway");
  }

  /// @notice When msg.value > 0, the native wrap is the sole WETH source: a zero-amount WETH input is
  ///         a no-op and no WETH is pulled from the wallet. Alice's ERC20 WETH balance is untouched.
  ///         (A positive-amount WETH input here is rejected — see the ConflictingWethInput test.)
  function test_swapAndDeposit_native_eth_does_not_pull_weth_from_wallet() public {
    vm.deal(ALICE, 4 ether);
    vm.startPrank(ALICE);
    mockWeth.deposit{ value: 3 ether }(); // Alice holds 3 WETH ERC20; has 1 ETH native left
    mockWeth.approve(address(gateway), type(uint256).max);
    vm.stopPrank();

    tokenA.mint(address(router), 100e18);
    tokenB.mint(address(router), 200e18);
    tokenC.mint(address(router), 50e6);
    tokenD.mint(address(router), 100e18);
    router.setRate(address(mockWeth), address(tokenA), 100e18, 1 ether);
    router.setRate(address(mockWeth), address(tokenB), 200e18, 1 ether);
    router.setRate(address(mockWeth), address(tokenC), 50e6, 1 ether);
    router.setRate(address(mockWeth), address(tokenD), 100e18, 1 ether);

    _approveGatewayAll(ALICE);

    // inputs[] declares WETH with amount 0 (a no-op): the native-ETH wrap is the sole WETH source,
    // so no WETH is pulled from the wallet. Each swap consumes 0.25 WETH from the wrapped balance.
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenA),
      20e18,
      _buildSwapCalldata(address(mockWeth), address(tokenA), 0.25 ether)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenB),
      40e18,
      _buildSwapCalldata(address(mockWeth), address(tokenB), 0.25 ether)
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenC),
      10e6,
      _buildSwapCalldata(address(mockWeth), address(tokenC), 0.25 ether)
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenD),
      20e18,
      _buildSwapCalldata(address(mockWeth), address(tokenD), 0.25 ether)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(mockWeth), 0), // no-op WETH input; native wrap is the sole WETH source
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    uint256 aliceWethBefore = mockWeth.balanceOf(ALICE); // 3 WETH

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit{ value: 1 ether }(params);

    assertGt(shares, 0, "shares received");
    // ERC20 WETH balance must be completely untouched — only native ETH (1 ETH) was used
    assertEq(mockWeth.balanceOf(ALICE), aliceWethBefore, "ERC20 WETH wallet balance never touched");
    assertEq(ALICE.balance, 0, "1 ETH consumed by native wrap");
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "no residual WETH in gateway");
    assertEq(address(gateway).balance, 0, "no residual ETH in gateway");
  }

  /// @notice Review fix: there is exactly one WETH source per call. Declaring a positive-amount WETH
  ///         input alongside native ETH (msg.value > 0) is rejected loudly, instead of silently
  ///         dropping the WETH input and under-depositing relative to the caller's intent.
  function test_swapAndDeposit_revertsWhenNativeEthCarriesPositiveWethInput() public {
    vm.deal(ALICE, 1 ether);

    // msg.value > 0 (native wrap) AND a WETH input with amount > 0 — a conflicting double WETH source.
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(mockWeth), 1 ether),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(SharedVaultGateway.ConflictingWethInput.selector);
    gateway.swapAndDeposit{ value: 1 ether }(params);
  }

  /// @notice A zero-amount WETH input alongside native ETH is allowed (it is simply a no-op): the
  ///         native wrap remains the sole WETH source and the call proceeds.
  function test_swapAndDeposit_allowsZeroAmountWethInputWithNativeEth() public {
    tokenA.mint(address(router), 100e18);
    tokenB.mint(address(router), 200e18);
    tokenC.mint(address(router), 50e6);
    tokenD.mint(address(router), 100e18);
    router.setRate(address(mockWeth), address(tokenA), 100e18, 1 ether);
    router.setRate(address(mockWeth), address(tokenB), 200e18, 1 ether);
    router.setRate(address(mockWeth), address(tokenC), 50e6, 1 ether);
    router.setRate(address(mockWeth), address(tokenD), 100e18, 1 ether);

    vm.deal(ALICE, 1 ether);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenA),
      20e18,
      _buildSwapCalldata(address(mockWeth), address(tokenA), 0.25 ether)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenB),
      40e18,
      _buildSwapCalldata(address(mockWeth), address(tokenB), 0.25 ether)
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenC),
      10e6,
      _buildSwapCalldata(address(mockWeth), address(tokenC), 0.25 ether)
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.25 ether,
      address(tokenD),
      20e18,
      _buildSwapCalldata(address(mockWeth), address(tokenD), 0.25 ether)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(mockWeth), 0), // zero-amount WETH input is a no-op, not a conflict
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit{ value: 1 ether }(params);
    assertGt(shares, 0, "zero-amount WETH input alongside native ETH is accepted");
  }

  /// @notice msg.value is wrapped to WETH; swap entry uses amountIn==0 to consume the full balance.
  function test_swapAndDeposit_native_eth_wraps_and_swaps_to_vault_tokens() public {
    // Fund the router with vault tokens that can be bought with WETH
    tokenA.mint(address(router), 100e18);
    tokenB.mint(address(router), 200e18);
    tokenC.mint(address(router), 50e6);
    tokenD.mint(address(router), 100e18);
    // Rate: 1 WETH → 100 tokenA (just a convenient ratio)
    router.setRate(address(mockWeth), address(tokenA), 100e18, 1 ether);
    router.setRate(address(mockWeth), address(tokenB), 200e18, 1 ether);
    router.setRate(address(mockWeth), address(tokenC), 50e6, 1 ether);
    router.setRate(address(mockWeth), address(tokenD), 100e18, 1 ether);

    vm.deal(ALICE, 4 ether);
    _approveGatewayAll(ALICE);

    // Four swaps: WETH (amountIn=0, full balance) → each vault token, each consuming 1 ETH
    // The swapData hard-codes the exact WETH amount so the router takes the right portion each time
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(mockWeth), 0, address(tokenA), 90e18, _buildSwapCalldata(address(mockWeth), address(tokenA), 1 ether)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(mockWeth), 0, address(tokenB), 180e18, _buildSwapCalldata(address(mockWeth), address(tokenB), 1 ether)
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(mockWeth), 0, address(tokenC), 45e6, _buildSwapCalldata(address(mockWeth), address(tokenC), 1 ether)
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(mockWeth), 0, address(tokenD), 90e18, _buildSwapCalldata(address(mockWeth), address(tokenD), 1 ether)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _emptyInputs(), // pure native ETH path; msg.value provides all WETH
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit{ value: 4 ether }(params);

    assertGt(shares, 0, "shares received from pure native-ETH deposit");
    assertEq(vault.balanceOf(ALICE), shares);
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "no residual WETH in gateway");
    assertEq(address(gateway).balance, 0, "no residual ETH in gateway");
  }

  /// @notice Excess msg.value beyond what swaps consume is unwrapped and returned as native ETH.
  function test_swapAndDeposit_native_eth_excess_returned_as_eth() public {
    tokenA.mint(address(router), 100e18);
    router.setRate(address(mockWeth), address(tokenA), 100e18, 1 ether); // 1 WETH → 100 tokenA

    // Alice also provides B, C, D so the deposit can succeed
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    vm.deal(ALICE, 3 ether); // sends 3 ETH but only 1 ETH worth of WETH is swapped

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    // Only 1 WETH is consumed by the router; 2 WETH remain and must be returned as ETH
    swaps[0] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0, // amountIn=0 → use full WETH balance for approval
      address(tokenA),
      90e18,
      _buildSwapCalldata(address(mockWeth), address(tokenA), 1 ether)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    gateway.swapAndDeposit{ value: 3 ether }(params);

    // 3 ETH sent, 1 used for the WETH→tokenA swap, 2 ETH worth of WETH unwrapped and returned
    assertEq(ALICE.balance, 2 ether, "2 ETH refunded from unused WETH");
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "no WETH stranded in gateway");
    assertEq(address(gateway).balance, 0, "no ETH stranded in gateway");
  }

  /// @notice Splitting native ETH across two distinct WETH→token swaps:
  ///         amountIn==0 so no transferFrom occurs; the router calldata governs each portion.
  function test_swapAndDeposit_native_eth_split_across_multiple_swaps() public {
    // 1 WETH (from 1 ETH) is split: 0.4 → tokenA, remaining 0.6 → tokenB
    tokenA.mint(address(router), 1000e18);
    tokenB.mint(address(router), 1000e18);
    router.setRate(address(mockWeth), address(tokenA), 100e18, 1 ether); // 0.4 WETH → 40 tokenA
    router.setRate(address(mockWeth), address(tokenB), 200e18, 1 ether); // 0.6 WETH → 120 tokenB

    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    vm.deal(ALICE, 1 ether);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    // Both WETH swaps consume from gateway balance; calldata governs each portion.
    swaps[0] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0.4 ether,
      address(tokenA),
      0,
      _buildSwapCalldata(address(mockWeth), address(tokenA), 0.4 ether)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(mockWeth),
      0,
      address(tokenB),
      0,
      _buildSwapAllCalldata(address(mockWeth), address(tokenB)) // swaps all remaining WETH
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs2(address(tokenC), 50e6, address(tokenD), 100e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit{ value: 1 ether }(params);

    assertGt(shares, 0, "shares received after split native ETH deposit");
    // All WETH consumed: 0.4 WETH → tokenA, 0.6 WETH → tokenB
    assertEq(ALICE.balance, 0, "all native ETH consumed");
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "no residual WETH in gateway");
    assertEq(address(gateway).balance, 0, "no residual ETH in gateway");
  }

  // ==================== WithdrawAndSwap: InsufficientWithdrawBalance ====================

  /// @notice Reverts when amountIn > balance of tokenIn after vault.withdraw().
  ///         Alice withdraws ~100 tokenA but the swap entry demands 200 tokenA.
  function test_withdrawAndSwap_fail_insufficient_balance_for_explicit_swap() public {
    uint256 shares = _depositForAlice();
    // Alice received ~100A, ~200B, ~50C, ~100D from her deposit (10% of the pool).
    // She asks to swap 200A → tokenX, but she only has ~100A — should revert on index 0.

    tokenX.mint(address(router), 1000e18);
    router.setRate(address(tokenA), address(tokenX), 1, 1);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      200e18, // more than the ~100A withdrawn
      address(tokenX),
      0,
      _buildSwapCalldata(address(tokenA), address(tokenX), 200e18)
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
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientWithdrawBalance.selector, 0));
    gateway.withdrawAndSwap(params);
  }

  /// @notice Reverts at the correct swap index when the first swap passes but a later one fails.
  function test_withdrawAndSwap_fail_insufficient_balance_reports_correct_index() public {
    uint256 shares = _depositForAlice();
    // index 0 (tokenA, 100e18) passes; index 1 (tokenB, 999e18) fails → revert with index 1.

    tokenX.mint(address(router), 1000e18);
    router.setRate(address(tokenA), address(tokenX), 1, 1);
    router.setRate(address(tokenB), address(tokenX), 1, 1);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      100e18, // exact — passes
      address(tokenX),
      0,
      _buildSwapCalldata(address(tokenA), address(tokenX), 100e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenB),
      999e18, // far above the ~200B withdrawn
      address(tokenX),
      0,
      _buildSwapCalldata(address(tokenB), address(tokenX), 999e18)
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
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientWithdrawBalance.selector, 1));
    gateway.withdrawAndSwap(params);
  }

  /// @notice Two swaps share the same tokenIn with individual amountIn values that each fit
  ///         within the withdrawn balance, but whose *sum* exceeds it.  With per-swap balance
  ///         checks, swap[0] (60e18 ≤ 100e18) executes and consumes 60A, then swap[1] (60e18
  ///         > 40A remaining) reverts at index 1.
  ///
  ///         Example: vault returns 100 tokenA. Swaps = [(tokenA→X, 60), (tokenA→X, 60)].
  ///         swap[0] succeeds; swap[1] fails → revert InsufficientWithdrawBalance(1).
  function test_withdrawAndSwap_fail_cumulative_amountIn_exceeds_balance() public {
    uint256 shares = _depositForAlice();
    // Alice has exactly 100e18 tokenA after withdraw (10% of 1000e18 pool).
    // Two swaps each ask for 60e18 tokenA → combined 120e18 > 100e18.
    // swap[0] executes (60A consumed), swap[1] then detects 40A < 60A → revert at index 1.
    tokenX.mint(address(router), 1000e18);
    router.setRate(address(tokenA), address(tokenX), 1, 1);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      60e18, // within balance — executes successfully
      address(tokenX),
      0,
      _buildSwapCalldata(address(tokenA), address(tokenX), 60e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenA),
      60e18, // only 40e18 remains after swap[0] → reverts
      address(tokenX),
      0,
      _buildSwapCalldata(address(tokenA), address(tokenX), 60e18)
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
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientWithdrawBalance.selector, 1));
    gateway.withdrawAndSwap(params);
  }

  /// @notice Multi-hop chain: explicit amountIn on an intermediate token (tokenX) that the
  ///         gateway holds zero of before any swap executes.  The old aggregate preflight check
  ///         would have reverted here because it read balances before execution; the per-swap
  ///         check succeeds because swap[0] produces tokenX before swap[1] checks it.
  function test_withdrawAndSwap_multihop_chain_succeeds() public {
    uint256 shares = _depositForAlice();
    // Alice has ~100A, ~200B, ~50C, ~100D from her 10%-proportional deposit.
    // Route: tokenA → tokenX → tokenB.  Gateway holds 0 tokenX before execution.
    tokenX.mint(address(router), 200e18); // router gives tokenX on swap[0]
    tokenB.mint(address(router), 200e18); // router gives tokenB on swap[1]
    router.setRate(address(tokenA), address(tokenX), 1, 1); // 100A → 100X
    router.setRate(address(tokenX), address(tokenB), 1, 1); // 100X → 100B

    uint256 chainAmount = 100e18;
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      chainAmount,
      address(tokenX),
      0,
      _buildSwapCalldata(address(tokenA), address(tokenX), chainAmount)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX),
      chainAmount, // zero before swap[0]; available after swap[0] produces it
      address(tokenB),
      0,
      _buildSwapCalldata(address(tokenX), address(tokenB), chainAmount)
    );

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: _sweepTokensArray(address(tokenX))
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params); // must not revert

    assertEq(tokenA.balanceOf(ALICE), 0, "All tokenA consumed in chain");
    assertGt(tokenB.balanceOf(ALICE), 0, "Alice received tokenB output from chain");
    assertEq(tokenX.balanceOf(address(gateway)), 0, "No residual tokenX in gateway");
  }

  /// @notice amountIn=0 swap entries bypass the balance check — they are "use full balance"
  ///         instructions and never revert in _checkSwapInputBalances, even when the entry
  ///         has swapData (the swap will either consume whatever is there or no-op).
  function test_withdrawAndSwap_amountIn_zero_skips_balance_check() public {
    uint256 shares = _depositForAlice();
    // Use full-balance (amountIn=0) swaps — check must not revert even though we don't
    // specify explicit amounts.
    tokenX.mint(address(router), 2000e18);
    router.setRate(address(tokenA), address(tokenX), 1, 1);
    router.setRate(address(tokenB), address(tokenX), 1, 1);
    router.setRate(address(tokenC), address(tokenX), 100e18, 50e6);
    router.setRate(address(tokenD), address(tokenX), 1, 1);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](4);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenA), address(tokenX))
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenB), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenB), address(tokenX))
    );
    swaps[2] = SharedVaultGateway.SwapParams(
      address(tokenC), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenC), address(tokenX))
    );
    swaps[3] = SharedVaultGateway.SwapParams(
      address(tokenD), 0, address(tokenX), 0, _buildSwapAllCalldata(address(tokenD), address(tokenX))
    );

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(vault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: swaps,
      sweepTokens: _sweepTokensArray(address(tokenX))
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params); // must not revert

    assertGt(tokenX.balanceOf(ALICE), 0, "Alice received tokenX from full-balance swaps");
    assertEq(tokenA.balanceOf(ALICE), 0);
    assertEq(tokenB.balanceOf(ALICE), 0);
    assertEq(tokenC.balanceOf(ALICE), 0);
    assertEq(tokenD.balanceOf(ALICE), 0);
  }

  /// @notice amountIn=0 resolves to the gateway's full tokenIn balance. If that balance is zero,
  ///         a nonzero amountOutMin must still be enforced rather than treating the swap as a no-op.
  function test_withdrawAndSwap_fail_full_balance_swap_with_zero_balance_and_min_out() public {
    uint256 shares = _depositForAlice();

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX), 0, address(tokenA), 1, _buildSwapAllCalldata(address(tokenX), address(tokenA))
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

  /// @notice Swap entries without swapData are skipped by _executeSwaps and never reach the per-swap balance check.
  function test_withdrawAndSwap_no_swapdata_skips_balance_check() public {
    uint256 shares = _depositForAlice();
    // A swap entry with empty swapData and amountIn > balance should NOT trigger the check.
    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenA),
      9999e18, // large amountIn, but swapData is empty
      address(tokenX),
      0,
      "" // no swapData → skipped
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
    gateway.withdrawAndSwap(params); // must not revert; tokenA swept to Alice

    assertGt(tokenA.balanceOf(ALICE), 0, "tokenA swept to Alice");
  }

  /// @notice The skip twin of the zero-balance revert above: a full-balance swap (amountIn == 0) on a
  ///         token the gateway never received resolves to zero and, with amountOutMin == 0, must be
  ///         skipped silently — the rest of the withdraw completes and the router is never called.
  function test_withdrawAndSwap_full_balance_swap_with_zero_balance_and_zero_min_out_is_skipped() public {
    uint256 shares = _depositForAlice();

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX), 0, address(tokenA), 0, _buildSwapAllCalldata(address(tokenX), address(tokenA))
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
    gateway.withdrawAndSwap(params); // must not revert — the dataful swap entry is a no-op

    assertGt(tokenA.balanceOf(ALICE), 0, "withdraw output swept to Alice despite the no-op swap entry");
    assertEq(tokenX.balanceOf(ALICE), 0, "no tokenX was conjured by the skipped swap");
  }

  /// @notice Empty swapData is only a skip instruction when no per-swap minimum output was requested.
  function test_withdrawAndSwap_fail_empty_swapdata_with_min_out() public {
    uint256 shares = _depositForAlice();

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(address(tokenA), 0, address(tokenX), 1, "");

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

  // ==================== WithdrawAndSwap: WETH unwrap in gateway ====================

  /// @dev Deploy a 2-token vault seeded with WETH and tokenA, deposit 1 WETH + 100 tokenA for Alice.
  function _setupWethVault() internal returns (SharedVault wethVault, uint256 aliceShares) {
    wethVault = new SharedVault();

    uint256 wethSeed = 10 ether;
    uint256 tokenASeed = 1000e18;

    vm.deal(address(this), wethSeed);
    mockWeth.deposit{ value: wethSeed }();
    tokenA.mint(address(this), tokenASeed);

    GatewayMockERC20(address(mockWeth)).transfer(address(wethVault), wethSeed);
    tokenA.transfer(address(wethVault), tokenASeed);

    address[4] memory vaultTokens = [address(mockWeth), address(tokenA), address(0), address(0)];
    uint256[4] memory initAmounts = [wethSeed, tokenASeed, 0, 0];

    vm.prank(VAULT_OWNER);
    wethVault.initialize(
      "WETH-TokenA Vault", vaultTokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );

    // Alice deposits 1 WETH (ERC20) + 100 tokenA = 10% of pool
    vm.deal(ALICE, 1 ether);
    vm.startPrank(ALICE);
    mockWeth.deposit{ value: 1 ether }();
    mockWeth.approve(address(gateway), type(uint256).max);
    vm.stopPrank();
    tokenA.mint(ALICE, 100e18);
    _approveGateway(address(tokenA), ALICE);
    _approveGateway(address(wethVault), ALICE);

    SharedVaultGateway.SwapAndDepositParams memory depositParams = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(wethVault)),
      inputs: _inputs2(address(mockWeth), 1 ether, address(tokenA), 100e18),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    aliceShares = gateway.swapAndDeposit(depositParams);
    require(aliceShares > 0, "setup: no shares minted");
  }

  /// @notice When unwrapOnWithdraw=true, vault.withdraw always receives WETH (unwrap=false),
  ///         then the gateway unwraps it and sends native ETH to the caller.
  function test_withdrawAndSwap_unwrapOnWithdraw_true_receives_eth() public {
    (SharedVault wethVault, uint256 aliceShares) = _setupWethVault();

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(wethVault)),
      shares: aliceShares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: true,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    uint256 aliceEthBefore = ALICE.balance;

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    // Alice receives native ETH (WETH unwrapped by gateway, not by vault)
    assertGt(ALICE.balance, aliceEthBefore, "Alice received ETH from unwrapped WETH");
    assertEq(mockWeth.balanceOf(ALICE), 0, "Alice holds no WETH");
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "No WETH stranded in gateway");
    assertEq(address(gateway).balance, 0, "No ETH stranded in gateway");
    assertEq(wethVault.balanceOf(ALICE), 0, "All shares burned");
  }

  /// @notice When unwrapOnWithdraw=false, vault.withdraw still receives WETH (unwrap=false),
  ///         and the gateway sweeps WETH directly to the caller without unwrapping.
  function test_withdrawAndSwap_unwrapOnWithdraw_false_receives_weth() public {
    (SharedVault wethVault, uint256 aliceShares) = _setupWethVault();

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(wethVault)),
      shares: aliceShares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    gateway.withdrawAndSwap(params);

    // Alice receives WETH (not ETH); gateway is clean
    assertGt(mockWeth.balanceOf(ALICE), 0, "Alice received WETH");
    assertEq(ALICE.balance, 0, "No ETH sent to Alice");
    assertEq(mockWeth.balanceOf(address(gateway)), 0, "No WETH stranded in gateway");
    assertEq(address(gateway).balance, 0, "No ETH stranded in gateway");
  }

  // ==================== SwapAndDeposit: InsufficientPostSwapBalance ====================

  function test_swapAndDeposit_fail_insufficient_post_swap_balance() public {
    tokenA.mint(ALICE, 1e18);
    vm.prank(ALICE);
    GatewayMockERC20(address(tokenA)).approve(address(gateway), type(uint256).max);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs1(address(tokenA), 1e18),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientPostSwapBalance.selector, 0));
    gateway.swapAndDeposit(params);
  }

  // ==================== SwapAndDeposit: Pull-then-split (10 USDC → 8 USDC + 2 WETH) ====================

  /// @notice The headline scenario for inputs[]/swaps[] separation: caller declares the
  ///         total they want to deposit (10 tokenC), and the gateway splits it internally —
  ///         2 tokenC go through the swap to produce tokenA, 8 tokenC are deposited directly.
  /// @dev Note: vault.deposit takes only the binding-ratio slice and returns the rest to the
  ///      gateway, which sweeps it back to the caller. So Alice's net tokenC outflow is
  ///      smaller than 10 — the important invariant is that the gateway pulled all 10
  ///      momentarily and finished with zero residual.
  function test_swapAndDeposit_pull_total_then_split_to_swap_and_direct() public {
    tokenA.mint(address(router), 100e18);
    // Rate: 1 tokenC (6 dec) → 2 tokenA (18 dec): outAmount = inAmount * 4e18 / 2e6
    router.setRate(address(tokenC), address(tokenA), 4e18, 2e6);

    // Alice provides B and D in proper proportion plus 10 tokenC (2 to swap, 8 direct).
    tokenC.mint(ALICE, 10e6);
    tokenB.mint(ALICE, 200e18);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenC),
      2e6,
      address(tokenA),
      3e18, // expect ~4 tokenA, accept ≥ 3
      _buildSwapCalldata(address(tokenC), address(tokenA), 2e6)
    );

    // inputs declares the *total* tokenC pull (10), even though only 2 are swapped.
    // The other 8 stay in the gateway and feed the deposit directly.
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenC), 10e6, address(tokenB), 200e18, address(tokenD), 100e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    uint256 aliceCBefore = tokenC.balanceOf(ALICE);

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "shares minted from split-input deposit");
    assertEq(tokenC.balanceOf(address(gateway)), 0, "no tokenC stranded in gateway");
    assertEq(tokenA.balanceOf(address(gateway)), 0, "no tokenA stranded in gateway");
    assertEq(tokenB.balanceOf(address(gateway)), 0, "no tokenB stranded in gateway");
    assertEq(tokenD.balanceOf(address(gateway)), 0, "no tokenD stranded in gateway");
    // Alice spent some tokenC into the vault (the binding-ratio amount, ≤ 10).
    assertGt(aliceCBefore, tokenC.balanceOf(ALICE), "Alice spent some tokenC");
    assertLe(aliceCBefore - tokenC.balanceOf(ALICE), 10e6, "no more than 10 tokenC could have left Alice");
  }

  /// @notice The bug this redesign fixes: under the old design, if a caller wrote a swap
  ///         entry that pulled less than the vault required (e.g. only 2 tokenC for the swap,
  ///         forgetting that the remaining 8 also needed to be pulled for direct deposit),
  ///         the deposit would proceed with insufficient balance and silently mint tiny shares.
  ///         Under the new design, `minDepositAmounts` catches this *and* the inputs[] field
  ///         makes the caller's intent explicit — under-declaring inputs simply doesn't pull
  ///         enough, and `InsufficientPostSwapBalance` reverts cleanly.
  function test_swapAndDeposit_under_declared_input_reverts_with_min_check() public {
    tokenA.mint(address(router), 100e18);
    router.setRate(address(tokenC), address(tokenA), 4e18, 2e6);

    tokenC.mint(ALICE, 10e6);
    tokenB.mint(ALICE, 200e18);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](1);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenC), 2e6, address(tokenA), 3e18, _buildSwapCalldata(address(tokenC), address(tokenA), 2e6)
    );

    // BUG SIMULATION: Alice (or the off-chain API) only declares 2 tokenC in inputs —
    // the amount needed for the swap — and forgets the 8 tokenC needed for direct deposit.
    // With minDepositAmounts[2] = 8e6 (the slot for tokenC), the post-swap balance check
    // catches the shortfall before vault.deposit is called.
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenC), 2e6, address(tokenB), 200e18, address(tokenD), 100e18),
      swaps: swaps,
      // Slot 2 corresponds to tokenC (vault token order: A, B, C, D). Require ≥ 8 tokenC after swap.
      minDepositAmounts: [uint256(0), uint256(0), uint256(8e6), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(SharedVaultGateway.InsufficientPostSwapBalance.selector, 2));
    gateway.swapAndDeposit(params);
  }

  /// @notice Two swap entries from the same input token: 100 tokenX pulled once,
  ///         then split internally into two swaps (60 → A, 40 → B).
  ///         Under the old design this required two pull entries totaling 100;
  ///         under the new design it is a single inputs[] entry of 100.
  function test_swapAndDeposit_single_input_feeds_multiple_swaps() public {
    tokenA.mint(address(router), 200e18);
    tokenB.mint(address(router), 200e18);
    router.setRate(address(tokenX), address(tokenA), 1, 1);
    router.setRate(address(tokenX), address(tokenB), 2, 1); // 1X → 2B

    tokenX.mint(ALICE, 100e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams(
      address(tokenX), 60e18, address(tokenA), 55e18, _buildSwapCalldata(address(tokenX), address(tokenA), 60e18)
    );
    swaps[1] = SharedVaultGateway.SwapParams(
      address(tokenX), 40e18, address(tokenB), 75e18, _buildSwapCalldata(address(tokenX), address(tokenB), 40e18)
    );

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs3(address(tokenX), 100e18, address(tokenC), 50e6, address(tokenD), 100e18),
      swaps: swaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);

    assertGt(shares, 0, "shares minted from one input feeding two swaps");
    assertEq(tokenX.balanceOf(address(gateway)), 0, "all tokenX consumed by the two swaps");
  }

  /// @notice inputs[] entries with amount=0 are no-ops (no transferFrom call).
  ///         This lets callers leave optional inputs in the payload without paying for a pull.
  function test_swapAndDeposit_zero_amount_input_is_skipped() public {
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    // tokenX has no allowance set, but the inputs[] entry has amount=0 — should not revert.
    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](5);
    inputs[0] = SharedVaultGateway.InputToken(address(tokenA), 100e18);
    inputs[1] = SharedVaultGateway.InputToken(address(tokenB), 200e18);
    inputs[2] = SharedVaultGateway.InputToken(address(tokenC), 50e6);
    inputs[3] = SharedVaultGateway.InputToken(address(tokenD), 100e18);
    inputs[4] = SharedVaultGateway.InputToken(address(tokenX), 0); // zero → skipped

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: inputs,
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);
    assertGt(shares, 0, "deposit succeeds with zero-amount input entry");
  }

  // ==================== Withdrawable Tests ====================

  // Allow this test contract to receive ETH so sweepNativeToken can transfer to address(this).
  receive() external payable { }

  function test_withdrawable_sweepNativeToken_owner_succeeds() public {
    vm.deal(address(gateway), 1 ether);
    uint256 ownerBefore = address(this).balance;

    gateway.sweepNativeToken(1 ether);

    assertEq(address(this).balance, ownerBefore + 1 ether);
    assertEq(address(gateway).balance, 0);
  }

  function test_withdrawable_sweepNativeToken_caps_at_balance() public {
    vm.deal(address(gateway), 0.5 ether);
    uint256 ownerBefore = address(this).balance;

    // Request more than balance — should sweep only what's available.
    gateway.sweepNativeToken(1 ether);

    assertEq(address(this).balance, ownerBefore + 0.5 ether);
    assertEq(address(gateway).balance, 0);
  }

  function test_withdrawable_sweepNativeToken_non_owner_reverts() public {
    vm.deal(address(gateway), 1 ether);

    vm.prank(ALICE);
    vm.expectRevert();
    gateway.sweepNativeToken(1 ether);
  }

  function test_withdrawable_sweepERC20_owner_succeeds() public {
    tokenA.mint(address(gateway), 100e18);
    uint256 ownerBefore = tokenA.balanceOf(address(this));

    address[] memory tokens = new address[](1);
    tokens[0] = address(tokenA);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100e18;

    gateway.sweepERC20(tokens, amounts);

    assertEq(tokenA.balanceOf(address(this)), ownerBefore + 100e18);
    assertEq(tokenA.balanceOf(address(gateway)), 0);
  }

  function test_withdrawable_sweepERC20_caps_at_balance() public {
    tokenA.mint(address(gateway), 50e18);
    uint256 ownerBefore = tokenA.balanceOf(address(this));

    address[] memory tokens = new address[](1);
    tokens[0] = address(tokenA);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 200e18; // more than balance

    gateway.sweepERC20(tokens, amounts);

    assertEq(tokenA.balanceOf(address(this)), ownerBefore + 50e18);
    assertEq(tokenA.balanceOf(address(gateway)), 0);
  }

  function test_withdrawable_sweepERC20_non_owner_reverts() public {
    tokenA.mint(address(gateway), 100e18);

    address[] memory tokens = new address[](1);
    tokens[0] = address(tokenA);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100e18;

    vm.prank(ALICE);
    vm.expectRevert();
    gateway.sweepERC20(tokens, amounts);
  }

  function test_withdrawable_sweepERC20_length_mismatch_reverts() public {
    address[] memory tokens = new address[](2);
    tokens[0] = address(tokenA);
    tokens[1] = address(tokenB);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100e18;

    vm.expectRevert(Withdrawable.ArrayLengthMismatch.selector);
    gateway.sweepERC20(tokens, amounts);
  }

  function test_withdrawable_sweepERC20_zero_address_reverts() public {
    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100e18;

    vm.expectRevert("ZeroAddress");
    gateway.sweepERC20(tokens, amounts);
  }

  function test_withdrawable_sweepERC721_owner_succeeds() public {
    GatewayMockERC721 nft = new GatewayMockERC721();
    nft.mint(address(gateway), 42);

    address[] memory tokens = new address[](1);
    tokens[0] = address(nft);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 42;

    gateway.sweepERC721(tokens, tokenIds);

    assertEq(nft.ownerOf(42), address(this), "owner received the swept NFT");
  }

  function test_withdrawable_sweepERC721_non_owner_reverts() public {
    GatewayMockERC721 nft = new GatewayMockERC721();
    nft.mint(address(gateway), 42);

    address[] memory tokens = new address[](1);
    tokens[0] = address(nft);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 42;

    vm.prank(ALICE);
    vm.expectRevert();
    gateway.sweepERC721(tokens, tokenIds);
  }

  function test_withdrawable_sweepERC1155_owner_succeeds() public {
    GatewayMockERC1155 multi = new GatewayMockERC1155();
    multi.mint(address(gateway), 7, 10);

    address[] memory tokens = new address[](1);
    tokens[0] = address(multi);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 7;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 10;

    gateway.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(multi.balanceOf(address(this), 7), 10, "owner received the swept ERC1155 balance");
    assertEq(multi.balanceOf(address(gateway), 7), 0, "gateway holds nothing after sweep");
  }

  function test_withdrawable_sweepERC1155_non_owner_reverts() public {
    GatewayMockERC1155 multi = new GatewayMockERC1155();
    multi.mint(address(gateway), 7, 10);

    address[] memory tokens = new address[](1);
    tokens[0] = address(multi);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 7;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 10;

    vm.prank(ALICE);
    vm.expectRevert();
    gateway.sweepERC1155(tokens, tokenIds, amounts);
  }

  // ==================== Input validation / lifecycle gaps ====================

  /// @notice _pullInputTokens requires every declared input token to be a real ERC20 address —
  ///         address(0) is never valid (native ETH travels via msg.value, not inputs[]).
  function test_swapAndDeposit_revertsOnZeroAddressInputToken() public {
    SharedVaultGateway.InputToken[] memory inputs = new SharedVaultGateway.InputToken[](1);
    inputs[0] = SharedVaultGateway.InputToken({ token: address(0), amount: 1e18 });

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: inputs,
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    vm.prank(ALICE);
    vm.expectRevert(SharedVaultGateway.ZeroAddress.selector);
    gateway.swapAndDeposit(params);
  }

  /// @notice Accept-side of the MAX_SWAPS boundary: exactly MAX_SWAPS entries must pass the batch
  ///         limit (the revert side at MAX_SWAPS + 1 is covered by
  ///         test_swapAndDeposit_revertsWhenSwapBatchExceedsPracticalBound). All-zero entries are
  ///         no-op skips (empty swapData with amountOutMin == 0), so the deposit completes.
  function test_swapAndDeposit_acceptsExactlyMaxSwapsNoOpEntries() public {
    tokenA.mint(ALICE, 100e18);
    tokenB.mint(ALICE, 200e18);
    tokenC.mint(ALICE, 50e6);
    tokenD.mint(ALICE, 100e18);
    _approveGatewayAll(ALICE);

    SharedVaultGateway.SwapParams[] memory noOpSwaps = new SharedVaultGateway.SwapParams[](100);

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(vault)),
      inputs: _inputs4(
        address(tokenA), 100e18, address(tokenB), 200e18, address(tokenC), 50e6, address(tokenD), 100e18
      ),
      swaps: noOpSwaps,
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    assertEq(noOpSwaps.length, gateway.MAX_SWAPS(), "boundary test must use exactly MAX_SWAPS entries");

    vm.prank(ALICE);
    uint256 shares = gateway.swapAndDeposit(params);
    assertGt(shares, 0, "deposit with exactly MAX_SWAPS no-op entries succeeds");
  }

  function test_initialize_revertsWhenCalledTwice() public {
    vm.expectRevert();
    gateway.initialize(address(this), address(router), address(mockWeth));
  }

  /// @notice _sweepNative must revert loudly (EthTransferFailed) when the recipient rejects native
  ///         ETH — silently keeping the user's unwrapped withdrawal in the gateway would strand funds.
  function test_withdrawAndSwap_revertsWhenEthRecipientRejectsNativeSweep() public {
    (SharedVault wethVault, uint256 aliceShares) = _setupWethVault();

    GatewayEthRejector rejector = new GatewayEthRejector(gateway);
    vm.prank(ALICE);
    wethVault.transfer(address(rejector), aliceShares);
    rejector.approveShares(address(wethVault));

    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(wethVault)),
      shares: aliceShares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: true,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    vm.expectRevert(SharedVaultGateway.EthTransferFailed.selector);
    rejector.callWithdrawAndSwap(params);
  }
}

/// @dev Minimal ERC721 for Withdrawable sweep tests on the gateway instance.
contract GatewayMockERC721 {
  mapping(uint256 => address) public ownerOf;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "not owner");
    ownerOf[tokenId] = to;
  }
}

/// @dev Minimal ERC1155 for Withdrawable sweep tests on the gateway instance.
contract GatewayMockERC1155 {
  mapping(uint256 => mapping(address => uint256)) internal balances;

  function mint(address to, uint256 id, uint256 amount) external {
    balances[id][to] += amount;
  }

  function balanceOf(address account, uint256 id) external view returns (uint256) {
    return balances[id][account];
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
    balances[id][from] -= amount;
    balances[id][to] += amount;
  }
}

/// @dev Share-holding caller with NO receive function: any native ETH sent to it fails, which is
///      exactly what test_withdrawAndSwap_revertsWhenEthRecipientRejectsNativeSweep needs to force
///      the gateway's _sweepNative EthTransferFailed branch.
contract GatewayEthRejector {
  SharedVaultGateway internal immutable gateway;

  constructor(SharedVaultGateway _gateway) {
    gateway = _gateway;
  }

  function approveShares(address shareToken) external {
    IERC20(shareToken).approve(address(gateway), type(uint256).max);
  }

  function callWithdrawAndSwap(SharedVaultGateway.WithdrawAndSwapParams memory params) external {
    gateway.withdrawAndSwap(params);
  }
}
