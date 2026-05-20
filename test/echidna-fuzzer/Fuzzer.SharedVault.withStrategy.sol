// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * Scenario: owner creates vault with non-zero feeBps, 2 players deposit.
 * Properties:
 *   1. totalSupply == sum of all share balances
 *   2. feeBps never changes
 *   3. No player profits (withdraws more WETH than deposited)
 *   4. Share price never decreases (modulo rounding)
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
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
  address public vault;

  uint16 public INITIAL_FEE_BPS;
  mapping(address => int256) public netWethDeposit;
  int256 public netAttackerCost;
  uint256 public lastSharePriceWad;

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

    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      address(owner),
      new address[](0),
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    uint16 feeBps = 500;
    INITIAL_FEE_BPS = feeBps;

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "WithFees", vaultTokens, initAmounts, feeBps);
    netWethDeposit[address(owner)] += int256(1 ether);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player1)] += int256(1 ether);

    player2.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player2)] += int256(1 ether);

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

  function advance_time(uint256 blocks) external {
    blocks = (blocks % 7200) + 1;
    hevm.roll(block.number + blocks);
    hevm.warp(block.timestamp + blocks * 2);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Direct WETH transfer to vault — no shares minted. Probes inflation-attack surface.
  function attacker_donateWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(attacker));
    if (bal == 0) return;
    amount = amount % bal + 1;

    uint256 supplyBefore = IERC20(vault).totalSupply();
    uint256 priceBefore = _sharePriceWad();

    hevm.prank(address(attacker));
    IERC20(SV_WETH).transfer(vault, amount);
    netAttackerCost += int256(amount);

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
    try player1.callDeposit(vault, amts, 200) {
      uint256 minted = player1.sharesBalance(vault) - sBefore;
      netWethDeposit[address(player1)] += int256(victimWeth);
      assert(minted > 0);
    } catch {}
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
    return _allPlayerProfitFunded();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function _doDeposit(SharedVaultPlayer player, uint256 wethAmount) internal {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(player));
    if (bal == 0) return;
    wethAmount = wethAmount % bal + 1;
    uint256[4] memory amounts = _proportionalAmounts(wethAmount);
    if (!_hasEnoughBalance(address(player), amounts)) return;

    uint256 priceBefore = _sharePriceWad();
    player.callDeposit(vault, amounts, 200);
    netWethDeposit[address(player)] += int256(wethAmount);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);

    uint256 priceAfter = _sharePriceWad();
    assert(priceAfter + 1e9 >= priceBefore);
    lastSharePriceWad = priceAfter;
  }

  function _doWithdraw(SharedVaultPlayer player, uint256 shares) internal {
    uint256 playerShares = player.sharesBalance(vault);
    if (playerShares == 0) return;
    shares = shares % playerShares + 1;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(player));
    player.callWithdraw(vault, shares, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(player));
    netWethDeposit[address(player)] -= int256(wethAfter - wethBefore);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(_allPlayerProfitFunded());
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);

    if (IERC20(vault).totalSupply() > 0) lastSharePriceWad = _sharePriceWad();
  }

  function _playerProfit(SharedVaultPlayer player) internal view returns (int256) {
    int256 net = netWethDeposit[address(player)];
    return net < 0 ? -net : int256(0);
  }

  function _allPlayerProfitFunded() internal view returns (bool) {
    int256 totalProfit = _playerProfit(owner) + _playerProfit(player1) + _playerProfit(player2);
    return totalProfit <= netAttackerCost + int256(1e9);
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

  function _sharePriceWad() internal view returns (uint256) {
    uint256 supply = IERC20(vault).totalSupply();
    if (supply == 0) return 0;
    return SharedVault(payable(vault)).getTotalBalances()[0] * 1e18 / supply;
  }
}
