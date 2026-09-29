// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { MultiSwapStrategy } from "../../contracts/private-vault/strategies/swap/MultiSwapStrategy.sol";

// ---------------------------------------------------------------------------
// MultiSwapStrategy sweeps the dust an LP action leaves in a private vault: the automator appends it to the same
// vault multicall and PrivateVault delegatecalls it. Swaps are best-effort — a failing swap is skipped instead of
// reverting the batch (and with it the LP action) — and the router must never keep an allowance on vault tokens.
//
// Prices used throughout: WETH = $4,000, AERO = $0.80, cbBTC = $100,000, so each dust balance is worth ~$1-2.
// ---------------------------------------------------------------------------

contract DustToken is ERC20 {
  uint8 private immutable _decimals;

  constructor(string memory symbol_, uint8 decimals_) ERC20(symbol_, symbol_) {
    _decimals = decimals_;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

/// @dev Aggregator mock: pulls `amountIn` of `tokenIn` from the caller (or takes it as `msg.value` when `tokenIn` is
///      address(0)) and pays `amountOut` of `tokenOut` to `recipient` from its own liquidity. Like a real aggregator,
///      it reverts when the output no longer meets `minAmountOut`.
contract MockAggregatorRouter {
  using SafeERC20 for IERC20;

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    uint256 minAmountOut,
    address recipient
  ) external payable {
    require(amountOut >= minAmountOut, "Return amount is not enough");
    if (tokenIn == address(0)) require(msg.value == amountIn, "Invalid msg.value");
    else IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).safeTransfer(recipient, amountOut);
  }
}

/// @dev Stand-in for an LP action such as V3UtilsStrategy.swapAndMint: delegatecalled by the vault, it deposits into
///      a pool, and whatever the pool does not take stays in the vault as dust.
contract MockLpStrategy {
  using SafeERC20 for IERC20;

  function addLiquidity(
    address pool,
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1
  ) external payable {
    IERC20(token0).safeTransfer(pool, amount0);
    IERC20(token1).safeTransfer(pool, amount1);
  }
}

contract MultiSwapStrategyTest is Test {
  address internal vaultOwner = makeAddr("vaultOwner");
  address internal automator = makeAddr("automator");
  address internal pool = makeAddr("pool");

  PrivateVault internal vault;
  PrivateConfigManager internal configManager;
  MultiSwapStrategy internal strategy;
  MockAggregatorRouter internal router;
  MockLpStrategy internal lpStrategy;

  DustToken internal weth;
  DustToken internal aero;
  DustToken internal cbBtc;
  DustToken internal usdc;

  function setUp() public {
    weth = new DustToken("WETH", 18);
    aero = new DustToken("AERO", 18);
    cbBtc = new DustToken("cbBTC", 8);
    usdc = new DustToken("USDC", 6);

    router = new MockAggregatorRouter();
    usdc.mint(address(router), 1_000_000e6);

    strategy = new MultiSwapStrategy(address(router));
    lpStrategy = new MockLpStrategy();

    // The automator is a whitelisted caller, so the vault only lets it delegatecall whitelisted strategies
    address[] memory targets = new address[](2);
    targets[0] = address(strategy);
    targets[1] = address(lpStrategy);
    address[] memory callers = new address[](1);
    callers[0] = automator;
    configManager = new PrivateConfigManager();
    configManager.initialize(vaultOwner, targets, callers, vaultOwner);

    vault = new PrivateVault();
    vault.initialize(vaultOwner, address(configManager), "Dust Vault");
  }

  // ============ SWEEPING DUST ============

  function test_sweeps_every_dust_token_into_the_target_token() public {
    weth.mint(address(vault), 0.0004e18);
    aero.mint(address(vault), 1.5e18);

    _sweep(_batch(_usdcSwap(address(weth), 0.0004e18, 1.6e6, 1.58e6), _usdcSwap(address(aero), 1.5e18, 1.2e6, 1.18e6)));

    assertEq(weth.balanceOf(address(vault)), 0);
    assertEq(aero.balanceOf(address(vault)), 0);
    assertEq(usdc.balanceOf(address(vault)), 2.8e6);
  }

  function test_failing_swap_is_skipped_and_the_remaining_swaps_still_run() public {
    weth.mint(address(vault), 0.0004e18);
    aero.mint(address(vault), 1.5e18);

    // WETH moved since the quote: the router now pays 1.5 USDC, below the 1.58 USDC minimum, so it reverts
    _sweep(_batch(_usdcSwap(address(weth), 0.0004e18, 1.5e6, 1.58e6), _usdcSwap(address(aero), 1.5e18, 1.2e6, 1.18e6)));

    assertEq(weth.balanceOf(address(vault)), 0.0004e18, "failed swap leaves its dust in the vault");
    assertEq(aero.balanceOf(address(vault)), 0);
    assertEq(usdc.balanceOf(address(vault)), 1.2e6);
  }

  function test_failing_dust_swap_does_not_revert_the_lp_action_in_the_same_multicall() public {
    weth.mint(address(vault), 1.0004e18);
    usdc.mint(address(vault), 4000e6);

    // The automator deposits 1 WETH + 4,000 USDC, then sweeps the WETH dust with a swap quoted for 0.0005 WETH.
    // The deposit only left 0.0004 WETH, so the router cannot pull the quoted amount and reverts.
    address[] memory targets = new address[](2);
    targets[0] = address(lpStrategy);
    targets[1] = address(strategy);
    bytes[] memory data = new bytes[](2);
    data[0] = abi.encodeCall(MockLpStrategy.addLiquidity, (pool, address(weth), 1e18, address(usdc), 4000e6));
    data[1] = abi.encodeCall(MultiSwapStrategy.multiSwap, (_batch(_usdcSwap(address(weth), 0.0005e18, 2e6, 1.98e6))));

    _multicall(targets, data);

    assertEq(weth.balanceOf(pool), 1e18, "LP deposit of WETH persisted");
    assertEq(usdc.balanceOf(pool), 4000e6, "LP deposit of USDC persisted");
    assertEq(weth.balanceOf(address(vault)), 0.0004e18, "dust stays in the vault for a later sweep");
  }

  // ============ ALLOWANCE HYGIENE ============

  function test_router_allowance_is_revoked_after_a_failed_swap() public {
    weth.mint(address(vault), 0.0004e18);

    _sweep(_batch(_usdcSwap(address(weth), 0.0004e18, 1.5e6, 1.58e6)));

    // A failed swap never pulls its tokens, so without the reset the full approval would linger
    assertEq(weth.balanceOf(address(vault)), 0.0004e18, "swap failed");
    assertEq(weth.allowance(address(vault), address(router)), 0);
  }

  function test_router_allowance_is_revoked_when_the_router_spends_less_than_approved() public {
    weth.mint(address(vault), 0.0005e18);

    // Approve 0.0005 WETH as a buffer while the quote only spends 0.0004 WETH
    MultiSwapStrategy.SwapParams memory bufferedSwap = MultiSwapStrategy.SwapParams({
      tokenIn: address(weth),
      amountIn: 0.0005e18,
      swapData: _usdcSwapData(address(weth), 0.0004e18, 1.6e6, 1.58e6)
    });
    _sweep(_batch(bufferedSwap));

    assertEq(weth.balanceOf(address(vault)), 0.0001e18, "router spent less than approved");
    assertEq(weth.allowance(address(vault), address(router)), 0);
  }

  // ============ NO-OP ENTRIES ============

  function test_entries_with_zero_amount_or_empty_swap_data_are_skipped() public {
    weth.mint(address(vault), 0.0004e18);

    // Neither entry may approve the router or call it
    vm.expectCall(address(weth), abi.encodeWithSelector(IERC20.approve.selector), 0);
    vm.expectCall(address(router), "", 0);

    _sweep(
      _batch(
        MultiSwapStrategy.SwapParams({
          tokenIn: address(weth),
          amountIn: 0,
          swapData: _usdcSwapData(address(weth), 0.0004e18, 1.6e6, 1.58e6)
        }),
        MultiSwapStrategy.SwapParams({ tokenIn: address(weth), amountIn: 0.0004e18, swapData: "" })
      )
    );

    assertEq(weth.balanceOf(address(vault)), 0.0004e18);
  }

  // ============ NATIVE DUST ============

  function test_native_dust_is_swapped_by_sending_value_to_the_router() public {
    vm.deal(address(vault), 0.0004 ether);

    _sweep(_batch(_usdcSwap(address(0), 0.0004 ether, 1.6e6, 1.58e6)));

    assertEq(address(vault).balance, 0);
    assertEq(usdc.balanceOf(address(vault)), 1.6e6);
  }

  function test_failed_native_swap_keeps_the_native_balance_in_the_vault() public {
    vm.deal(address(vault), 0.0004 ether);

    _sweep(_batch(_usdcSwap(address(0), 0.0004 ether, 1.5e6, 1.58e6)));

    assertEq(address(vault).balance, 0.0004 ether);
    assertEq(usdc.balanceOf(address(vault)), 0);
  }

  // ============ OBSERVABILITY ============

  function test_emits_the_outcome_of_every_attempted_swap_from_the_vault() public {
    weth.mint(address(vault), 0.0004e18);
    aero.mint(address(vault), 1.5e18);

    // The vault is the emitter because the strategy runs in the vault's context via delegatecall
    vm.expectEmit(address(vault));
    emit MultiSwapStrategy.SwapAttempted(0, address(weth), 0.0004e18, false);
    vm.expectEmit(address(vault));
    emit MultiSwapStrategy.SwapAttempted(1, address(aero), 1.5e18, true);

    _sweep(_batch(_usdcSwap(address(weth), 0.0004e18, 1.5e6, 1.58e6), _usdcSwap(address(aero), 1.5e18, 1.2e6, 1.18e6)));
  }

  // ============ VAULT INTEGRATION ============

  function test_runs_inside_a_multicall_that_carries_native_value() public {
    weth.mint(address(vault), 0.0004e18);

    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeCall(MultiSwapStrategy.multiSwap, (_batch(_usdcSwap(address(weth), 0.0004e18, 1.6e6, 1.58e6))));
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;

    // DELEGATECALL keeps the multicall's msg.value, so a non-payable multiSwap would revert the whole batch
    vm.deal(vaultOwner, 1 ether);
    vm.prank(vaultOwner);
    vault.multicall{ value: 1 ether }(targets, new uint256[](1), data, callTypes);

    assertEq(usdc.balanceOf(address(vault)), 1.6e6);
  }

  function test_automator_cannot_sweep_until_the_strategy_is_whitelisted() public {
    weth.mint(address(vault), 0.0004e18);

    address[] memory revoked = new address[](1);
    revoked[0] = address(strategy);
    vm.prank(vaultOwner);
    configManager.setWhitelistTargets(revoked, false);

    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeCall(MultiSwapStrategy.multiSwap, (_batch(_usdcSwap(address(weth), 0.0004e18, 1.6e6, 1.58e6))));

    vm.expectRevert(abi.encodeWithSelector(IPrivateVault.InvalidTarget.selector, address(strategy)));
    _multicall(targets, data);

    assertEq(weth.balanceOf(address(vault)), 0.0004e18);
    assertEq(usdc.balanceOf(address(vault)), 0);
  }

  // ============ CONSTRUCTOR ============

  function test_constructor_rejects_a_zero_swap_router() public {
    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    new MultiSwapStrategy(address(0));
  }

  // ============ FUZZ ============

  function testFuzz_any_mix_of_failing_swaps_never_reverts_nor_leaves_an_allowance(bool[3] memory fails) public {
    DustToken[3] memory dust = [weth, aero, cbBtc];
    uint256[3] memory amounts = [uint256(0.0004e18), 1.5e18, 0.00001e8];
    uint256[3] memory quotes = [uint256(1.6e6), 1.2e6, 1e6];

    MultiSwapStrategy.SwapParams[] memory swaps = new MultiSwapStrategy.SwapParams[](3);
    uint256 expectedUsdc;
    for (uint256 i; i < 3; i++) {
      dust[i].mint(address(vault), amounts[i]);
      // A failing swap demands 1 wei more than the router pays, so the router reverts on slippage
      swaps[i] = _usdcSwap(address(dust[i]), amounts[i], quotes[i], fails[i] ? quotes[i] + 1 : quotes[i]);
      if (!fails[i]) expectedUsdc += quotes[i];
    }

    _sweep(swaps);

    for (uint256 i; i < 3; i++) {
      assertEq(dust[i].balanceOf(address(vault)), fails[i] ? amounts[i] : 0);
      assertEq(dust[i].allowance(address(vault), address(router)), 0);
    }
    assertEq(usdc.balanceOf(address(vault)), expectedUsdc);
  }

  // ============ HELPERS ============

  /// @dev Sells `amountIn` of `tokenIn` (approving exactly that much) for `quotedOut` USDC paid to the vault. The
  ///      router reverts when `quotedOut` is below `minOut`.
  function _usdcSwap(
    address tokenIn,
    uint256 amountIn,
    uint256 quotedOut,
    uint256 minOut
  ) internal view returns (MultiSwapStrategy.SwapParams memory) {
    return
      MultiSwapStrategy.SwapParams({
        tokenIn: tokenIn,
        amountIn: amountIn,
        swapData: _usdcSwapData(tokenIn, amountIn, quotedOut, minOut)
      });
  }

  function _usdcSwapData(
    address tokenIn,
    uint256 amountIn,
    uint256 quotedOut,
    uint256 minOut
  ) internal view returns (bytes memory) {
    return
      abi.encodeCall(MockAggregatorRouter.swap, (tokenIn, address(usdc), amountIn, quotedOut, minOut, address(vault)));
  }

  function _batch(
    MultiSwapStrategy.SwapParams memory a
  ) internal pure returns (MultiSwapStrategy.SwapParams[] memory swaps) {
    swaps = new MultiSwapStrategy.SwapParams[](1);
    swaps[0] = a;
  }

  function _batch(
    MultiSwapStrategy.SwapParams memory a,
    MultiSwapStrategy.SwapParams memory b
  ) internal pure returns (MultiSwapStrategy.SwapParams[] memory swaps) {
    swaps = new MultiSwapStrategy.SwapParams[](2);
    swaps[0] = a;
    swaps[1] = b;
  }

  /// @dev Sweeps the way the automator does: a vault multicall that delegatecalls the strategy.
  function _sweep(MultiSwapStrategy.SwapParams[] memory swaps) internal {
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeCall(MultiSwapStrategy.multiSwap, (swaps));
    _multicall(targets, data);
  }

  function _multicall(address[] memory targets, bytes[] memory data) internal {
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](targets.length);
    for (uint256 i; i < targets.length; i++) {
      callTypes[i] = IPrivateCommon.CallType.DELEGATECALL;
    }
    vm.prank(automator);
    vault.multicall(targets, new uint256[](targets.length), data, callTypes);
  }
}
