// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * Scenario: owner opens/closes LP positions while players deposit/withdraw.
 * Properties:
 *   1. vaultOwnerFeeBasisPoint never changes after init
 *   2. totalSupply == sum of all player share balances
 *   3. No player withdraws more WETH than deposited
 *   4. Depositing never dilutes existing holders (share price must not decrease)
 *   5. Collecting fees never decreases share price
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import "./IHevm.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract SharedVaultFuzzerWithStrategy {
  IHevm internal hevm = IHevm(SV_HEVM_ADDRESS);

  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedVaultPlayer public attacker;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedV3Strategy public v3Strategy;
  address public vault;

  uint16 public immutable INITIAL_FEE_BPS;
  mapping(address => int256) public netWethDeposit;

  // Share price = totalValue / totalSupply; tracked in WETH wei per share (scaled ×1e18).
  // Depositing must never decrease existing holders' redemption value.
  uint256 public lastSharePriceWad;

  // ── Shadow accountant (differential model) ──────────────────────────────────
  mapping(address => uint256) public shadowSharesMinted;
  mapping(address => uint256) public shadowSharesBurned;
  uint256 public shadowDepositsWadSum; // Σ (wethValueIn × 1e18) at deposit time

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    owner = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();
    attacker = new SharedVaultPlayer();

    _fundWeth(address(owner), SV_INITIAL_WETH);
    _fundWeth(address(player1), SV_INITIAL_WETH);
    _fundWeth(address(player2), SV_INITIAL_WETH);
    _fundWeth(address(attacker), SV_INITIAL_WETH);
    _fundUsdc(address(owner), SV_INITIAL_USDC);
    _fundUsdc(address(player1), SV_INITIAL_USDC);
    _fundUsdc(address(player2), SV_INITIAL_USDC);
    _fundUsdc(address(attacker), SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(SV_V3UTILS, address(lpFeeTaker));

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;

    configManager = new SharedConfigManager();
    configManager.initialize(address(owner), targets, new address[](0), SV_FEE_RECIPIENT, 0, nfpms, new address[](0));

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    uint16 feeBps = 500; // 5%
    INITIAL_FEE_BPS = feeBps;

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "WithStrategy", vaultTokens, initAmounts, feeBps);
    netWethDeposit[address(owner)] += int256(1 ether);
    _recordDeposit(owner, 1 ether, owner.sharesBalance(vault));

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    uint256 sharesBefore1 = player1.sharesBalance(vault);
    player1.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player1)] += int256(1 ether);
    _recordDeposit(player1, 1 ether, player1.sharesBalance(vault) - sharesBefore1);

    uint256 sharesBefore2 = player2.sharesBalance(vault);
    player2.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player2)] += int256(1 ether);
    _recordDeposit(player2, 1 ether, player2.sharesBalance(vault) - sharesBefore2);

    lastSharePriceWad = _sharePriceWad();
  }

  // ── Fuzzed actions ──────────────────────────────────────────────────────────

  function player1_deposit(uint256 wethAmount) external {
    _doDeposit(player1, wethAmount);
  }

  function player2_deposit(uint256 wethAmount) external {
    _doDeposit(player2, wethAmount);
  }

  function player1_withdraw(uint256 shares) external {
    _doWithdraw(player1, shares);
  }

  function player2_withdraw(uint256 shares) external {
    _doWithdraw(player2, shares);
  }

  function owner_withdraw(uint256 shares) external {
    _doWithdraw(owner, shares);
  }

  function owner_deposit(uint256 wethAmount) external {
    _doDeposit(owner, wethAmount);
  }

  /// @dev Collect accrued LP fees for all open positions.
  ///      Fee collection changes idle balances without touching share supply — a prime
  ///      target for share-price manipulation if fee accounting is wrong.
  function owner_collectFees() external {
    uint256 posCount = SharedVault(payable(vault)).getPositionCount();
    if (posCount == 0) return;

    uint16 feeBps = SharedVault(payable(vault)).vaultOwnerFeeBasisPoint();
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](posCount);
    for (uint256 i; i < posCount; i++) {
      (, address nfpm, uint256 tokenId,,) = SharedVault(payable(vault)).getPosition(i);
      actions[i] = ISharedVault.Action({
        target: address(v3Strategy),
        data: abi.encodeCall(ISharedStrategy.collectFees, (nfpm, tokenId, feeBps)),
        callType: ISharedCommon.CallType.DELEGATECALL
      });
    }

    owner.callExecute(vault, actions);

    // fee collection must not alter share supply or fee bps
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
    // share price must not decrease after collecting fees (fees increase idle, so price should rise or stay)
    uint256 newPrice = _sharePriceWad();
    assert(newPrice + 1e9 >= lastSharePriceWad); // 1e9 wei tolerance for rounding
    lastSharePriceWad = newPrice;
  }

  /// @dev Close any tracked position by index — lets echidna stress multi-position accounting.
  function owner_closePositionAt(uint256 index) external {
    uint256 posCount = SharedVault(payable(vault)).getPositionCount();
    if (posCount == 0) return;
    index = index % posCount;

    (, address nfpm, uint256 tokenId,,) = SharedVault(payable(vault)).getPosition(index);
    uint256 totalSupply = IERC20(vault).totalSupply();

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(v3Strategy),
      data: abi.encodeCall(
        ISharedStrategy.exitProportional,
        (nfpm, tokenId, totalSupply, totalSupply, 0, 0, SharedVault(payable(vault)).vaultOwnerFeeBasisPoint())
      ),
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    owner.callExecute(vault, actions);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Advance time so LP fees accrue; lets echidna explore post-fee-accrual deposit/withdraw paths.
  function advance_time(uint256 blocks) external {
    blocks = (blocks % 7200) + 1; // cap at ~1 day of Base blocks
    hevm.roll(block.number + blocks);
    hevm.warp(block.timestamp + blocks * 2); // ~2s per block on Base

    // invariants must hold across time jumps
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Fully close the first tracked LP position via exitProportional delegatecall.
  ///      Mirrors what withdraw() does internally, but lets echidna trigger it independently
  ///      so it can explore open→close→reopen sequences.
  function owner_closeLpPosition() external {
    if (SharedVault(payable(vault)).getPositionCount() == 0) return;

    (, address nfpm, uint256 tokenId,,) = SharedVault(payable(vault)).getPosition(0);
    uint256 totalSupply = IERC20(vault).totalSupply();

    bytes memory callData = abi.encodeCall(
      ISharedStrategy.exitProportional,
      (nfpm, tokenId, totalSupply, totalSupply, 0, 0, SharedVault(payable(vault)).vaultOwnerFeeBasisPoint())
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(v3Strategy),
      data: callData,
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    owner.callExecute(vault, actions);

    // after full close: supply and fee unchanged, position count decreased
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Open a wide-range WETH/USDC LP position using half the vault's idle WETH + matching USDC.
  ///      Uses SV_TICK_LOWER/SV_TICK_UPPER (near full-range) so the position stays in-range regardless
  ///      of price drift during the fuzzing session.
  function owner_openLpPosition() external {
    uint256[4] memory idle = SharedVault(payable(vault)).getIdleBalances();
    if (idle[0] < 0.1 ether) return; // not enough idle WETH to be worth minting

    uint256 amt0 = idle[0] / 2;
    uint256 amt1 = idle[1] / 2;

    address[] memory approveTokens = new address[](2);
    approveTokens[0] = SV_WETH;
    approveTokens[1] = SV_USDC;
    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amt0;
    approveAmounts[1] = amt1;

    // WETH < USDC by address on Base, so token0=WETH, token1=USDC
    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0, // Uniswap V3-compatible
      nfpm: SV_NFPM,
      token0: SV_WETH,
      token1: SV_USDC,
      fee: SV_POOL_FEE,
      tickSpacing: 10,
      tickLower: SV_TICK_LOWER,
      tickUpper: SV_TICK_UPPER,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: amt0,
      amount1: amt1,
      amount2: 0,
      recipient: address(0), // overwritten by strategy to address(this)
      deadline: block.timestamp + 300,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      poolDeployer: address(0)
    });

    bytes memory strategyData = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.SWAP_AND_MINT),
      abi.encode(params, approveTokens, approveAmounts, uint256(0))
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(v3Strategy),
      data: strategyData,
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    owner.callExecute(vault, actions);

    // totalSupply and fee must be unaffected by LP position management
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  // ── Adversarial actions ─────────────────────────────────────────────────────

  /// @dev Direct WETH transfer to vault — no shares minted. Probes inflation-attack surface.
  function attacker_donateWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(attacker));
    if (bal == 0) return;
    amount = amount % bal + 1;

    uint256 priceBefore = _sharePriceWad();
    uint256 supplyBefore = IERC20(vault).totalSupply();

    hevm.prank(address(attacker));
    IERC20(SV_WETH).transfer(vault, amount);

    // Supply unchanged — attacker just gifted value.
    assert(IERC20(vault).totalSupply() == supplyBefore);
    uint256 priceAfter = _sharePriceWad();
    assert(priceAfter >= priceBefore);
    lastSharePriceWad = priceAfter;

    // Immediate victim deposit must still mint non-zero shares (inflation-attack check).
    uint256 victimWeth = 0.01 ether;
    if (IERC20(SV_WETH).balanceOf(address(player1)) < victimWeth) return;
    uint256[4] memory amts = _proportionalAmounts(victimWeth);
    if (!_hasEnoughBalance(address(player1), amts)) return;

    uint256 sBefore = player1.sharesBalance(vault);
    try player1.callDeposit(vault, amts, 10_000) {
      uint256 minted = player1.sharesBalance(vault) - sBefore;
      netWethDeposit[address(player1)] += int256(victimWeth);
      _recordDeposit(player1, victimWeth, minted);
      assert(minted > 0);
    } catch {}
  }

  /// @dev Drain every holder, then re-deposit — exercises totalSupply==0 transition.
  function drain_all_then_redeposit(uint256 wethAmount) external {
    _fullWithdraw(owner);
    _fullWithdraw(player1);
    _fullWithdraw(player2);

    assert(IERC20(vault).totalSupply() == 0);
    assert(netWethDeposit[address(owner)] >= -int256(1e9));
    assert(netWethDeposit[address(player1)] >= -int256(1e9));
    assert(netWethDeposit[address(player2)] >= -int256(1e9));

    uint256 bal = IERC20(SV_WETH).balanceOf(address(player1));
    if (bal == 0) return;
    wethAmount = wethAmount % bal + 1;
    uint256[4] memory amts = _proportionalAmounts(wethAmount);
    if (!_hasEnoughBalance(address(player1), amts)) return;

    uint256 sBefore = player1.sharesBalance(vault);
    player1.callDeposit(vault, amts, 200);
    uint256 minted = player1.sharesBalance(vault) - sBefore;
    netWethDeposit[address(player1)] += int256(wethAmount);
    _recordDeposit(player1, wethAmount, minted);

    // First depositor into an empty vault must receive non-zero shares.
    assert(minted > 0);
    if (IERC20(vault).totalSupply() > 0) lastSharePriceWad = _sharePriceWad();
  }

  // ── Properties ──────────────────────────────────────────────────────────────

  function echidna_fee_bps_immutable() external view returns (bool) {
    return SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS;
  }

  function echidna_share_supply_consistent() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    return supply == sumBalances;
  }

  function echidna_no_player_profits() external view returns (bool) {
    return _playerNetOk(owner) && _playerNetOk(player1) && _playerNetOk(player2);
  }

  /// @dev Shadow share accounting: per-player balance must equal Σ minted − Σ burned.
  function echidna_shadow_share_accounting() external view returns (bool) {
    return _shadowOk(owner) && _shadowOk(player1) && _shadowOk(player2);
  }

  /// @dev Avg deposit price (WETH per share) must not exceed current share price beyond a
  ///      bounded drift — depositors collectively should not lose value without an event.
  function echidna_solvency() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    if (supply == 0) return true;
    uint256 totalMinted = shadowSharesMinted[address(owner)]
      + shadowSharesMinted[address(player1)]
      + shadowSharesMinted[address(player2)];
    if (totalMinted == 0) return true;
    uint256 avgDepositPriceWad = shadowDepositsWadSum / totalMinted;
    uint256 currentPriceWad = SharedVault(payable(vault)).getTotalBalances()[0] * 1e18 / supply;
    return currentPriceWad + 1e12 >= avgDepositPriceWad;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function _doDeposit(SharedVaultPlayer player, uint256 wethAmount) internal {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(player));
    if (bal == 0) return;
    wethAmount = wethAmount % bal + 1;
    uint256[4] memory amounts = _proportionalAmounts(wethAmount);
    if (!_hasEnoughBalance(address(player), amounts)) return;

    uint256 priceBefore = _sharePriceWad();
    uint256 sharesBefore = player.sharesBalance(vault);
    player.callDeposit(vault, amounts, 200);
    uint256 sharesMinted = player.sharesBalance(vault) - sharesBefore;
    netWethDeposit[address(player)] += int256(wethAmount);
    _recordDeposit(player, wethAmount, sharesMinted);

    // totalSupply must equal sum of all share balances after every deposit
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);

    // fee basis point must never change
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);

    // deposit must not dilute existing holders — share price must not decrease
    uint256 priceAfter = _sharePriceWad();
    assert(priceAfter + 1e9 >= priceBefore); // 1e9 wei tolerance for rounding
    lastSharePriceWad = priceAfter;
  }

  function _doWithdraw(SharedVaultPlayer player, uint256 shares) internal {
    uint256 playerShares = player.sharesBalance(vault);
    if (playerShares == 0) return;
    shares = shares % playerShares + 1;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(player));
    uint256 sharesBefore = playerShares;
    player.callWithdraw(vault, shares, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(player));
    uint256 sharesBurned = sharesBefore - player.sharesBalance(vault);
    netWethDeposit[address(player)] -= int256(wethAfter - wethBefore);
    _recordWithdraw(player, sharesBurned);

    // totalSupply must equal sum of all share balances after every withdrawal
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);

    // no player should ever withdraw more WETH than they deposited (with tiny rounding tolerance)
    assert(netWethDeposit[address(player)] >= -int256(1e9));

    // fee basis point must never change
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);

    // update tracked price after withdrawal (fees paid out can legitimately move price)
    if (IERC20(vault).totalSupply() > 0) lastSharePriceWad = _sharePriceWad();
  }

  function _playerNetOk(SharedVaultPlayer player) internal view returns (bool) {
    return netWethDeposit[address(player)] >= -int256(1e9);
  }

  function _fundWeth(address actor, uint256 amount) internal {
    hevm.deal(actor, amount);
    hevm.startPrank(actor);
    IWETH(SV_WETH).deposit{ value: amount }();
    hevm.stopPrank();
  }

  function _fundUsdc(address actor, uint256 amount) internal {
    hevm.startPrank(SV_USDC_WHALE);
    IERC20(SV_USDC).transfer(actor, amount);
    hevm.stopPrank();
  }

  function _proportionalAmounts(uint256 wethAmount) internal view returns (uint256[4] memory amounts) {
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    amounts[0] = wethAmount;
    if (totals[0] > 0 && totals[1] > 0) {
      amounts[1] = wethAmount * totals[1] / totals[0] + 1;
    }
  }

  function _hasEnoughBalance(address actor, uint256[4] memory amounts) internal view returns (bool) {
    return IERC20(SV_WETH).balanceOf(actor) >= amounts[0] && IERC20(SV_USDC).balanceOf(actor) >= amounts[1];
  }

  // Returns WETH per share scaled by 1e18, using getTotalBalances()[0] which includes
  // WETH value of all open LP positions as priced by the strategy.
  function _recordDeposit(SharedVaultPlayer player, uint256 wethValueIn, uint256 sharesMinted) internal {
    shadowSharesMinted[address(player)] += sharesMinted;
    shadowDepositsWadSum += wethValueIn * 1e18;
  }

  function _recordWithdraw(SharedVaultPlayer player, uint256 sharesBurned) internal {
    shadowSharesBurned[address(player)] += sharesBurned;
  }

  function _shadowOk(SharedVaultPlayer p) internal view returns (bool) {
    uint256 actual = p.sharesBalance(vault);
    uint256 expected = shadowSharesMinted[address(p)] - shadowSharesBurned[address(p)];
    return actual == expected;
  }

  function _fullWithdraw(SharedVaultPlayer p) internal {
    uint256 s = p.sharesBalance(vault);
    if (s == 0) return;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(p));
    p.callWithdraw(vault, s, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(p));
    netWethDeposit[address(p)] -= int256(wethAfter - wethBefore);
    _recordWithdraw(p, s);
  }

  function _sharePriceWad() internal view returns (uint256) {
    uint256 supply = IERC20(vault).totalSupply();
    if (supply == 0) return 0;
    return SharedVault(payable(vault)).getTotalBalances()[0] * 1e18 / supply;
  }
}
