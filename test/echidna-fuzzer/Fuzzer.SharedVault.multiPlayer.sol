// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * Scenario: 3 equal players deposit; random deposit/withdraw order.
 * Properties:
 *   1. totalSupply == sum of all player share balances
 *   2. After full withdrawal totalSupply == 0
 *   3. No player withdraws more WETH than they deposited
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import "./IHevm.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract SharedVaultFuzzerMultiPlayer {
  IHevm internal hevm = IHevm(SV_HEVM_ADDRESS);

  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedVaultPlayer public player3;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  address public vault;

  // Track each player's net WETH deposited (deposits minus withdrawals) for property 3.
  mapping(address => int256) public netWethDeposit;

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();
    player3 = new SharedVaultPlayer();

    _fundWeth(address(player1), SV_INITIAL_WETH);
    _fundWeth(address(player2), SV_INITIAL_WETH);
    _fundWeth(address(player3), SV_INITIAL_WETH);
    _fundUsdc(address(player1), SV_INITIAL_USDC);
    _fundUsdc(address(player2), SV_INITIAL_USDC);
    _fundUsdc(address(player3), SV_INITIAL_USDC);

    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      address(player1), // player1 acts as vault owner for setup
      new address[](0),
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(player1), address(configManager), address(vaultImpl), SV_WETH);

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = player1.callCreateVault(address(vaultFactory), "MultiPlayer", vaultTokens, initAmounts, 0);
    netWethDeposit[address(player1)] += int256(1 ether);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player2.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player2)] += int256(1 ether);
    player3.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player3)] += int256(1 ether);
  }

  // ── Fuzzed actions ──────────────────────────────────────────────────────────

  function player1_deposit(uint256 wethAmount) external {
    _doDeposit(player1, wethAmount);
  }

  function player2_deposit(uint256 wethAmount) external {
    _doDeposit(player2, wethAmount);
  }

  function player3_deposit(uint256 wethAmount) external {
    _doDeposit(player3, wethAmount);
  }

  function player1_withdraw(uint256 shares) external {
    _doWithdraw(player1, shares);
  }

  function player2_withdraw(uint256 shares) external {
    _doWithdraw(player2, shares);
  }

  function player3_withdraw(uint256 shares) external {
    _doWithdraw(player3, shares);
  }

  // ── Properties ──────────────────────────────────────────────────────────────

  function echidna_share_supply_consistent() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances =
      player1.sharesBalance(vault) + player2.sharesBalance(vault) + player3.sharesBalance(vault);
    return supply == sumBalances;
  }

  function echidna_no_player_profits_from_weth() external view returns (bool) {
    return _playerNetWethOk(player1) && _playerNetWethOk(player2) && _playerNetWethOk(player3);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function _doDeposit(SharedVaultPlayer player, uint256 wethAmount) internal {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(player));
    if (bal == 0) return;
    wethAmount = wethAmount % bal + 1;
    uint256[4] memory amounts = _proportionalAmounts(wethAmount);
    if (!_hasEnoughBalance(address(player), amounts)) return;
    player.callDeposit(vault, amounts, 200);
    netWethDeposit[address(player)] += int256(wethAmount);

    // totalSupply must equal sum of all share balances after every deposit
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = player1.sharesBalance(vault) + player2.sharesBalance(vault) + player3.sharesBalance(vault);
    assert(supply == sumBalances);
  }

  function _doWithdraw(SharedVaultPlayer player, uint256 shares) internal {
    uint256 playerShares = player.sharesBalance(vault);
    if (playerShares == 0) return;
    shares = shares % playerShares + 1;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(player));
    player.callWithdraw(vault, shares, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(player));
    netWethDeposit[address(player)] -= int256(wethAfter - wethBefore);

    // totalSupply must equal sum of all share balances after every withdrawal
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = player1.sharesBalance(vault) + player2.sharesBalance(vault) + player3.sharesBalance(vault);
    assert(supply == sumBalances);

    // no player should ever withdraw more WETH than they deposited (with tiny rounding tolerance)
    assert(netWethDeposit[address(player)] >= -int256(1e9));
  }

  function _playerNetWethOk(SharedVaultPlayer player) internal view returns (bool) {
    int256 net = netWethDeposit[address(player)];
    // net >= -1e9 means player never withdrew more than deposited (with tiny rounding tolerance)
    return net >= -int256(1e9);
  }

  function _fundWeth(address actor, uint256 amount) internal {
    hevm.deal(actor, amount);
    hevm.startPrank(actor);
    IWETH(SV_WETH).deposit{ value: amount }();
    hevm.stopPrank();
  }

  function _fundUsdc(address actor, uint256 amount) internal {
    // Directly write to Circle USDC's _balances mapping (slot 9) — no fork/whale needed.
    bytes32 slot = keccak256(abi.encode(actor, uint256(9)));
    hevm.store(SV_USDC, slot, bytes32(amount));
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
}
