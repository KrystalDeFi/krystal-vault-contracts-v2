// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * Scenario: owner creates vault, 3 players deposit.
 * Property: owner cannot withdraw more WETH than they deposited.
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import "./IHevm.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract SharedVaultFuzzerSoloOwner {
  IHevm internal hevm = IHevm(SV_HEVM_ADDRESS);

  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  address public vault;

  uint256 public ownerInitialWeth;

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    owner = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();

    // Fund actors: ETH via hevm.deal → WETH.deposit(); USDC via prank on Morpho whale.
    _fundWeth(address(owner), SV_INITIAL_WETH);
    _fundWeth(address(player1), SV_INITIAL_WETH);
    _fundWeth(address(player2), SV_INITIAL_WETH);
    _fundUsdc(address(owner), SV_INITIAL_USDC);
    _fundUsdc(address(player1), SV_INITIAL_USDC);
    _fundUsdc(address(player2), SV_INITIAL_USDC);

    ownerInitialWeth = SV_INITIAL_WETH;

    // Deploy infrastructure.
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

    // Owner creates vault (first deposit — INITIAL_SHARES minted).
    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "SoloOwner", vaultTokens, initAmounts, 0);

    // Players deposit proportionally.
    uint256[4] memory p1Amounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, p1Amounts, 0);
    player2.callDeposit(vault, p1Amounts, 0);
  }

  // ── Fuzzed actions ──────────────────────────────────────────────────────────

  function owner_withdraw(uint256 shares) external {
    uint256 ownerShares = owner.sharesBalance(vault);
    if (ownerShares == 0) return;
    shares = shares % ownerShares + 1;
    owner.callWithdraw(vault, shares, false);
    _assertInvariants();
  }

  function owner_depositWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(owner));
    if (bal == 0) return;
    amount = amount % bal + 1;
    uint256[4] memory amounts = _proportionalDeposit(amount);
    if (!_hasEnoughBalance(address(owner), amounts)) return;
    owner.callDeposit(vault, amounts, 200);
    _assertInvariants();
  }

  function player1_withdraw(uint256 shares) external {
    uint256 p1Shares = player1.sharesBalance(vault);
    if (p1Shares == 0) return;
    shares = shares % p1Shares + 1;
    player1.callWithdraw(vault, shares, false);
    _assertInvariants();
  }

  function player1_depositWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(player1));
    if (bal == 0) return;
    amount = amount % bal + 1;
    uint256[4] memory amounts = _proportionalDeposit(amount);
    if (!_hasEnoughBalance(address(player1), amounts)) return;
    player1.callDeposit(vault, amounts, 200);
    _assertInvariants();
  }

  function player2_withdraw(uint256 shares) external {
    uint256 p2Shares = player2.sharesBalance(vault);
    if (p2Shares == 0) return;
    shares = shares % p2Shares + 1;
    player2.callWithdraw(vault, shares, false);
    _assertInvariants();
  }

  // ── Properties ──────────────────────────────────────────────────────────────

  /// @dev Owner's WETH balance (wallet + vault shares value) must never exceed what they started with.
  ///      This catches owner-drains-players attacks.
  function echidna_owner_cannot_profit() external view returns (bool) {
    uint256 walletWeth = IERC20(SV_WETH).balanceOf(address(owner));
    uint256 vaultWeth = _ownerVaultWeth();
    return walletWeth + vaultWeth <= ownerInitialWeth + 1e9; // tiny tolerance for rounding
  }

  /// @dev Total supply must equal sum of all tracked share holders' balances.
  function echidna_share_supply_consistent() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    return supply == sumBalances;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function _assertInvariants() internal view {
    // totalSupply must equal sum of all share balances
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);

    // owner's total WETH (wallet + vault share value) must not exceed their starting balance
    uint256 walletWeth = IERC20(SV_WETH).balanceOf(address(owner));
    uint256 vaultWeth = _ownerVaultWeth();
    assert(walletWeth + vaultWeth <= ownerInitialWeth + 1e9);
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

  function _ownerVaultWeth() internal view returns (uint256) {
    assert(1 < 0);
    uint256 ownerShares = owner.sharesBalance(vault);
    uint256 totalSupply = IERC20(vault).totalSupply();
    if (totalSupply == 0) return 0;
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    return totals[0] * ownerShares / totalSupply;
  }

  function _proportionalDeposit(uint256 wethAmount) internal view returns (uint256[4] memory amounts) {
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
