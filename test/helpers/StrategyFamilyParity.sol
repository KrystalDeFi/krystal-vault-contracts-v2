// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";

import { FaithfulERC20, FaithfulWETH9 } from "./FaithfulTokens.sol";

/// @dev SharedVault plus a passthrough that delegatecalls a strategy entry point with test-chosen arguments, so the
///      strategy runs in a real vault's storage and context (same pattern as SharedVaultCollectHarness).
contract ParityVault is SharedVault {
  function callStrategy(address strategy, bytes calldata data) external returns (bytes memory result) {
    bool ok;
    (ok, result) = strategy.delegatecall(data);
    if (!ok) {
      assembly ("memory-safe") {
        revert(add(result, 32), mload(result))
      }
    }
  }
}

/// @dev Cross-family parity suite: the same properties run against every shared strategy family, with the real
///      SharedVault, SharedConfigManager and strategy over the faithful protocol mocks in test/helpers/Faithful*.
///      Each concrete suite implements the adapter hooks for one family. Every world is a vault that alice seeded
///      with both tokens and that holds a live, in-range position the operator handed over.
abstract contract StrategyFamilyParityBase is Test {
  uint16 internal constant PLATFORM_BPS = 1000;
  uint16 internal constant OWNER_BPS = 500;
  int24 internal constant TICK_LOWER = -600;
  int24 internal constant TICK_UPPER = 600;
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;
  uint256 internal constant SEED = 100e18;
  uint256 internal constant POSITION = 100e18;
  uint256 internal constant SWAP_FEE0 = 2e18;
  uint256 internal constant SWAP_FEE1 = 3e18;
  /// @dev Required non-zero by the strategy constructors; no path in these suites swaps.
  address internal constant SWAP_ROUTER = address(0xD00D);

  address internal vaultOwner = makeAddr("parityVaultOwner");
  address internal operator = makeAddr("parityOperator");
  address internal feeRecipient = makeAddr("parityFeeRecipient");
  address internal alice = makeAddr("parityAlice");
  address internal bob = makeAddr("parityBob");

  FaithfulERC20 internal token0;
  FaithfulERC20 internal token1;
  FaithfulWETH9 internal weth;
  SharedConfigManager internal cm;
  ParityVault internal vault;
  address internal strategy;
  address internal nfpm;
  uint256 internal tokenId;

  // ---- family adapter ----

  /// @dev Deploys the protocol mocks for a token0/token1 pool at a 1:1 price, and the family's strategy.
  function _deployFamily() internal virtual returns (address nfpm_, address strategy_);

  /// @dev Mints a [TICK_LOWER, TICK_UPPER] position to `owner`, funded by `owner`, through the protocol's own mint.
  function _mintPosition(address owner, uint256 amount0, uint256 amount1) internal virtual returns (uint256 id);

  /// @dev The position's liquidity as the protocol records it.
  function _liquidityOf(uint256 id) internal view virtual returns (uint128);

  /// @dev Fees the protocol would pay the position on its next collect, from the mock's own ledger.
  function _uncollectedFees(uint256 id) internal view virtual returns (uint256 fees0, uint256 fees1);

  /// @dev Credits LP fees to the pool the way swaps do; this test contract pays the fee tokens.
  function _accrueFees(uint256 fee0, uint256 fee1) internal virtual;

  /// @dev Where the pool keeps its tokens.
  function _custody() internal view virtual returns (address);

  /// @dev No ERC-20 (or Permit2) allowance from the vault to the protocol is left behind.
  function _assertNoApprovalsLeft() internal view virtual;

  /// @dev Strategy `execute` payloads (no swaps, no gas fee, no minimums).
  function _compoundData(uint256 id) internal view virtual returns (bytes memory);

  function _decreaseData(uint256 id, uint128 liquidity) internal view virtual returns (bytes memory);

  function _increaseData(uint256 id, uint256 amount0, uint256 amount1) internal view virtual returns (bytes memory);

  // ---- depositProportional at an unchanged price ----

  /// @dev Off-ratio slice: ten times more token0 than the range takes at this price. The top-up succeeds with no
  ///      floor, a 0.5% floor and a 5% floor, deploys the binding side in full and leaves the excess idle.
  function test_topUp_offRatioSlice_noSlippageFloor() public {
    _checkOffRatioTopUp(0);
  }

  function test_topUp_offRatioSlice_halfPercentFloor() public {
    _checkOffRatioTopUp(50);
  }

  function test_topUp_offRatioSlice_fivePercentFloor() public {
    _checkOffRatioTopUp(500);
  }

  /// @dev A slice worth zero liquidity (1 wei of token0 alone, while the in-range position needs both tokens) is a
  ///      no-op: no revert, nothing leaves the vault, the position is unchanged.
  function test_topUp_zeroLiquiditySlice_isNoop() public {
    _setUpWorld(false);
    uint128 liquidityBefore = _liquidityOf(tokenId);
    uint256 vault0 = token0.balanceOf(address(vault));
    uint256 vault1 = token1.balanceOf(address(vault));
    uint256 custody0 = token0.balanceOf(_custody());
    uint256 custody1 = token1.balanceOf(_custody());

    vault.callStrategy(
      strategy, abi.encodeCall(ISharedStrategy.depositProportional, (nfpm, tokenId, uint256(1), uint256(0), 50))
    );

    assertEq(token0.balanceOf(address(vault)), vault0, "token0 stays in the vault");
    assertEq(token1.balanceOf(address(vault)), vault1, "token1 stays in the vault");
    assertEq(token0.balanceOf(_custody()), custody0, "nothing reached the pool");
    assertEq(token1.balanceOf(_custody()), custody1, "nothing reached the pool");
    assertEq(_liquidityOf(tokenId), liquidityBefore, "position unchanged");
    _assertNoApprovalsLeft();
  }

  // ---- native-ETH deposit ----

  function test_nativeEthDeposit_withLivePosition() public {
    _checkNativeEthDeposit();
  }

  // ---- valuation ----

  /// @dev The strategy's valuation reads the state the protocol keeps: the fee part equals the pool ledger's
  ///      uncollected fees and the principal is what the position was minted from (less pool rounding).
  function test_valuation_matchesProtocolLedger() public {
    (uint256 fees0, uint256 fees1) = _setUpWorldWithFees();
    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      ISharedStrategy(strategy).getPositionAmountsSplit(nfpm, tokenId);
    assertEq(total0 - principal0, fees0, "token0 fees valued as the ledger owes them");
    assertEq(total1 - principal1, fees1, "token1 fees valued as the ledger owes them");
    assertApproxEqRel(principal0, POSITION, 1e12, "token0 principal");
    assertApproxEqRel(principal1, POSITION, 1e12, "token1 principal");
  }

  // ---- fees are charged exactly once ----
  // Every path below starts from a position holding uncollected fees (fees0, fees1) read from the mock's ledger.
  // Afterwards the fee recipient and the vault owner must each hold exactly one cut of those fees and the position
  // must owe nothing. Paths that leave the fees on the position are followed by a small withdraw, whose
  // collect realises them; the property is the same whether a family charges during the path or at that collect.

  /// @dev Withdraw: the vault collects and charges the fees before the proportional exit; principal is not charged.
  function test_fees_withdraw_chargedOnce() public {
    (uint256 fees0, uint256 fees1) = _setUpWorldWithFees();
    _withdrawShareOf(alice, 10);
    _assertChargedOnce(fees0, fees1);
  }

  /// @dev Compound: fees are collected and charged once; the net fees go back into the position.
  function test_fees_compound_chargedOnce() public {
    (uint256 fees0, uint256 fees1) = _setUpWorldWithFees();
    uint128 liquidityBefore = _liquidityOf(tokenId);
    _execute(_compoundData(tokenId));
    _assertChargedOnce(fees0, fees1);
    assertGt(_liquidityOf(tokenId), liquidityBefore, "net fees compounded");
  }

  /// @dev Decrease: fees are charged once and the removed principal is not charged.
  function test_fees_decrease_chargedOnce() public {
    (uint256 fees0, uint256 fees1) = _setUpWorldWithFees();
    uint128 liquidityBefore = _liquidityOf(tokenId);
    _execute(_decreaseData(tokenId, liquidityBefore / 2));
    _assertChargedOnce(fees0, fees1);
    assertEq(_liquidityOf(tokenId), liquidityBefore - liquidityBefore / 2, "half the liquidity removed");
  }

  /// @dev Deposit top-up, with no slippage floor and with a 0.5% floor.
  function test_fees_depositTopUp_chargedOnce() public {
    _checkDepositTopUpCharges(0);
  }

  function test_fees_depositTopUpWithSlippageFloor_chargedOnce() public {
    _checkDepositTopUpCharges(50);
  }

  /// @dev Operator increase through execute.
  function test_fees_increase_chargedOnce() public {
    (uint256 fees0, uint256 fees1) = _setUpWorldWithFees();
    uint128 liquidityBefore = _liquidityOf(tokenId);
    _execute(_increaseData(tokenId, 10e18, 10e18));
    assertGt(_liquidityOf(tokenId), liquidityBefore, "liquidity increased");
    _withdrawShareOf(alice, 1);
    _assertChargedOnce(fees0, fees1);
  }

  // ---- shared checks ----

  function _checkOffRatioTopUp(uint16 slippageBps) internal {
    _setUpWorld(false);
    uint256 supplied0 = 10e18;
    uint256 supplied1 = 1e18;
    uint128 liquidityBefore = _liquidityOf(tokenId);
    uint256 vault0 = token0.balanceOf(address(vault));
    uint256 vault1 = token1.balanceOf(address(vault));
    uint256 custody0 = token0.balanceOf(_custody());
    uint256 custody1 = token1.balanceOf(_custody());

    vault.callStrategy(
      strategy, abi.encodeCall(ISharedStrategy.depositProportional, (nfpm, tokenId, supplied0, supplied1, slippageBps))
    );

    uint256 spent0 = vault0 - token0.balanceOf(address(vault));
    uint256 spent1 = vault1 - token1.balanceOf(address(vault));
    assertLe(spent0, supplied0, "never spends more token0 than supplied");
    assertLe(spent1, supplied1, "never spends more token1 than supplied");
    assertEq(spent1, supplied1, "the binding side is deployed in full");
    assertGt(spent0, 0, "an in-range top-up takes both tokens");
    assertLt(spent0, supplied0 / 2, "the excess token0 stays idle");
    assertEq(token0.balanceOf(_custody()) - custody0, spent0, "token0 that left the vault reached the pool");
    assertEq(token1.balanceOf(_custody()) - custody1, spent1, "token1 that left the vault reached the pool");
    assertGt(_liquidityOf(tokenId), liquidityBefore, "the slice was added to the position");
    _assertNoApprovalsLeft();
  }

  function _checkDepositTopUpCharges(uint16 slippageBps) internal {
    (uint256 fees0, uint256 fees1) = _setUpWorldWithFees();
    uint128 liquidityBefore = _liquidityOf(tokenId);
    uint256[4] memory amounts = _depositAmounts(10);
    assertGt(vault.previewDeposit(amounts), 0, "the vault's preview accepts these amounts");
    _fund(bob, token0, amounts[0]);
    _fund(bob, token1, amounts[1]);
    vm.startPrank(bob);
    token0.approve(address(vault), amounts[0]);
    token1.approve(address(vault), amounts[1]);
    uint256 shares = vault.deposit(amounts, slippageBps, 0);
    vm.stopPrank();
    assertGt(shares, 0, "deposit minted shares");
    assertGt(_liquidityOf(tokenId), liquidityBefore, "the deposit topped the position up");
    _withdrawShareOf(alice, 1);
    _assertChargedOnce(fees0, fees1);
  }

  /// @dev Native-ETH deposit into a vault that holds a live position of this family: the top-up runs inside the
  ///      payable deposit, the excess ETH is refunded, and the shares match the same deposit paid in WETH.
  function _checkNativeEthDeposit() internal {
    _setUpWorld(true);
    uint256 wi = address(token0) == address(weth) ? 0 : 1;
    FaithfulERC20 other = wi == 0 ? token1 : token0;
    uint128 liquidityBefore = _liquidityOf(tokenId);
    uint256[4] memory amounts = _depositAmounts(10);
    amounts[wi] *= 2;
    assertGt(vault.previewDeposit(amounts), 0, "the vault's preview accepts these amounts");
    other.mint(bob, amounts[1 - wi]);
    vm.prank(bob);
    other.approve(address(vault), type(uint256).max);
    vm.deal(bob, amounts[wi]);
    uint256 snapshot = vm.snapshotState();

    vm.prank(bob);
    uint256 sharesPaidInEth = vault.deposit{ value: amounts[wi] }(amounts, 0, 0);
    uint256 ethSpent = amounts[wi] - bob.balance;
    assertGt(_liquidityOf(tokenId), liquidityBefore, "the position was topped up inside the payable deposit");
    assertGt(ethSpent, 0, "ETH was used");
    assertLt(ethSpent, amounts[wi], "the excess ETH was refunded");
    assertEq(address(vault).balance, 0, "no raw ETH left in the vault");

    vm.revertToState(snapshot);
    vm.startPrank(bob);
    weth.deposit{ value: amounts[wi] }();
    weth.approve(address(vault), type(uint256).max);
    uint256 sharesPaidInWeth = vault.deposit(amounts, 0, 0);
    vm.stopPrank();
    assertEq(sharesPaidInEth, sharesPaidInWeth, "ETH and WETH deposits mint the same shares");
    assertEq(ethSpent, amounts[wi] - weth.balanceOf(bob), "ETH spent equals WETH pulled");
  }

  /// @dev Exactly one platform cut and one owner cut of the realised fees, and nothing left on the position.
  function _assertChargedOnce(uint256 fees0, uint256 fees1) internal view {
    assertEq(token0.balanceOf(feeRecipient), FullMath.mulDiv(fees0, PLATFORM_BPS, 10_000), "platform cut, token0");
    assertEq(token1.balanceOf(feeRecipient), FullMath.mulDiv(fees1, PLATFORM_BPS, 10_000), "platform cut, token1");
    assertEq(token0.balanceOf(vaultOwner), FullMath.mulDiv(fees0, OWNER_BPS, 10_000), "owner cut, token0");
    assertEq(token1.balanceOf(vaultOwner), FullMath.mulDiv(fees1, OWNER_BPS, 10_000), "owner cut, token1");
    (uint256 left0, uint256 left1) = _uncollectedFees(tokenId);
    assertEq(left0, 0, "no token0 fees left on the position");
    assertEq(left1, 0, "no token1 fees left on the position");
  }

  // ---- world ----

  function _setUpWorld(bool withWeth) internal {
    FaithfulERC20 a;
    if (withWeth) {
      weth = new FaithfulWETH9();
      a = weth;
    } else {
      a = new FaithfulERC20("TKA", 18);
    }
    FaithfulERC20 b = new FaithfulERC20("TKB", 18);
    (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
    (nfpm, strategy) = _deployFamily();

    cm = new SharedConfigManager();
    cm.initialize(
      address(this),
      _one(strategy),
      new address[](0),
      feeRecipient,
      PLATFORM_BPS,
      _one(nfpm),
      new address[](0),
      new address[](0)
    );
    vault = new ParityVault();
    vault.initialize(
      "Parity",
      [address(token0), address(token1), address(0), address(0)],
      [uint256(0), 0, 0, 0],
      vaultOwner,
      operator,
      address(cm),
      address(weth),
      OWNER_BPS
    );

    _fund(alice, token0, SEED);
    _fund(alice, token1, SEED);
    vm.startPrank(alice);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    vault.deposit([SEED, SEED, 0, 0], 0, 0);
    vm.stopPrank();

    tokenId = _mintPosition(operator, POSITION, POSITION);
    vm.startPrank(operator);
    IERC721(nfpm).approve(address(vault), tokenId);
    vault.recoverPosition(nfpm, tokenId, strategy, address(token0), address(token1));
    vm.stopPrank();
  }

  function _setUpWorldWithFees() internal returns (uint256 fees0, uint256 fees1) {
    _setUpWorld(false);
    _accrueFees(SWAP_FEE0, SWAP_FEE1);
    (fees0, fees1) = _uncollectedFees(tokenId);
    assertGt(fees0, 0, "token0 fees accrued");
    assertGt(fees1, 0, "token1 fees accrued");
  }

  /// @dev WETH is funded through deposit so every WETH stays ETH-backed.
  function _fund(address who, FaithfulERC20 token, uint256 amount) internal {
    if (address(token) == address(weth)) {
      vm.deal(who, who.balance + amount);
      vm.prank(who);
      weth.deposit{ value: amount }();
    } else {
      token.mint(who, amount);
    }
  }

  /// @dev `percent`% of the vault's total balances plus its minimum deposit amounts, from the vault's own views.
  function _depositAmounts(uint256 percent) internal view returns (uint256[4] memory amounts) {
    uint256[4] memory total = vault.getTotalBalances();
    uint256[4] memory minimum = vault.getMinDepositAmounts();
    for (uint256 i; i < 2; ++i) {
      amounts[i] = (total[i] * percent) / 100 + minimum[i];
    }
  }

  function _withdrawShareOf(address holder, uint256 percent) internal {
    uint256 shares = (vault.balanceOf(holder) * percent) / 100;
    vm.prank(holder);
    vault.withdraw(shares, [uint256(0), 0, 0, 0], false);
  }

  function _execute(bytes memory data) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({ target: strategy, data: data, callType: ISharedCommon.CallType.DELEGATECALL });
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function _one(address a) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
  }
}
