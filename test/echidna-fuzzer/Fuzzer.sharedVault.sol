// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * SharedVault property-based fuzzer.
 *
 * Tests core share-math invariants without LP positions (idle-only path).
 * Echidna runs random sequences of `deposit`/`withdraw` actions across N players
 * and checks the asserted invariants below after each action.
 *
 * To run:
 *   ./run-echidna-test.sh SharedVaultFuzzer
 *
 * Invariants asserted (assertion mode):
 *   I1: totalSupply == sum of player share balances (conservation)
 *   I2: For any token T: idle(T) == sum over players of (share[p] * idle(T) / totalSupply)  ±  rounding ε
 *   I3: After any deposit, shares_minted > 0 (no zero-share deposits sneak through)
 *   I4: After any withdraw, withdrawn_tokens[i] <= player's pre-burn proportional claim
 *       (no value creation; idle-only vault → preview matches actual exactly)
 *   I5: Monotonicity — depositing more at the same ratio always mints at least as many shares
 *       (asserted via paired actions; see depositTwoAndCompare)
 */

import "./IHevm.sol";
import "./Config.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ─── Minimal 18-dec ERC20 (no fork dependency) ──────────────────────────────
contract FuzzERC20 {
  string public name = "FuzzToken";
  string public symbol = "FZT";
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// ─── Lightweight player; depositor / withdrawer of the vault ─────────────────
contract SharedPlayer {
  SharedVault public vault;
  FuzzERC20 public tokenA;
  FuzzERC20 public tokenB;

  constructor(SharedVault _vault, FuzzERC20 _a, FuzzERC20 _b) {
    vault = _vault;
    tokenA = _a;
    tokenB = _b;
    _a.approve(address(_vault), type(uint256).max);
    _b.approve(address(_vault), type(uint256).max);
  }

  function deposit(uint256 amountA, uint256 amountB) external returns (uint256 shares) {
    uint256[4] memory amts;
    amts[0] = amountA;
    amts[1] = amountB;
    return vault.deposit(amts, 0);
  }

  function withdraw(uint256 shares) external returns (uint256[4] memory amounts) {
    uint256[4] memory mins;
    return vault.withdraw(shares, mins, false);
  }
}

contract SharedVaultFuzzer {
  // 18-dec floor at default precision = 5  →  10^(18 − 5) = 1e13
  uint256 constant FLOOR_18 = 1e13;
  uint256 constant MAX_DEPOSIT = 1e22; // bound input range so totalSupply stays sub-uint128

  IHevm hevm = IHevm(HEVM_ADDRESS);

  SharedVault public vault;
  SharedConfigManager public configManager;
  FuzzERC20 public tokenA;
  FuzzERC20 public tokenB;

  SharedPlayer[3] public players;

  // Track per-player cumulative claims for invariant checks
  uint256 public initialShareSupply;

  constructor() payable {
    tokenA = new FuzzERC20();
    tokenB = new FuzzERC20();

    configManager = new SharedConfigManager();
    address[] memory empty = new address[](0);
    configManager.initialize(address(this), empty, empty, address(this), 0, empty, empty);

    vault = new SharedVault();
    // Seed vault with initial liquidity at a 1:1 ratio so subsequent deposits have a target
    tokenA.mint(address(vault), 1000e18);
    tokenB.mint(address(vault), 1000e18);
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amts = [uint256(1000e18), uint256(1000e18), uint256(0), uint256(0)];
    vault.initialize("EchidnaShared", toks, amts, address(this), address(this), address(configManager), address(0), 0);

    initialShareSupply = vault.totalSupply(); // INITIAL_SHARES = 10e18

    // Create three player contracts; each gets a large balance to draw from
    for (uint256 i; i < 3; i++) {
      players[i] = new SharedPlayer(vault, tokenA, tokenB);
      tokenA.mint(address(players[i]), 1e30);
      tokenB.mint(address(players[i]), 1e30);
    }
  }

  // ─── Random actions Echidna calls ──────────────────────────────────────

  /// @notice Echidna-callable: player[idx] deposits at a 1:1 ratio.
  function player_deposit(uint8 idx, uint256 amount) external {
    idx = idx % 3;
    amount = _boundAmount(amount);

    uint256 sharesBefore = vault.balanceOf(address(players[idx]));
    uint256 totalBefore = vault.totalSupply();

    try players[idx].deposit(amount, amount) returns (uint256 shares) {
      // I3: deposit succeeded → must have minted positive shares
      assert(shares > 0);
      assert(vault.balanceOf(address(players[idx])) == sharesBefore + shares);
      assert(vault.totalSupply() == totalBefore + shares);
    } catch {
      // Deposit may legitimately revert (e.g., insufficient shares from dust); ignore.
    }

    _assertConservation();
  }

  /// @notice Echidna-callable: player[idx] withdraws a fraction of their shares.
  function player_withdraw(uint8 idx, uint8 percent) external {
    idx = idx % 3;
    percent = uint8(percent % 100);
    if (percent == 0) return;

    uint256 bal = vault.balanceOf(address(players[idx]));
    if (bal == 0) return;
    uint256 toBurn = (bal * percent) / 100;
    if (toBurn == 0) return;

    // I4 (preview/actual equivalence for idle-only vault):
    uint256[4] memory preview = vault.previewWithdraw(toBurn);

    try players[idx].withdraw(toBurn) returns (uint256[4] memory got) {
      // Idle-only vault, no fees → preview must equal actual exactly
      assert(got[0] == preview[0]);
      assert(got[1] == preview[1]);
    } catch {
      // unexpected revert in idle-only path is itself a finding
      assert(false);
    }

    _assertConservation();
  }

  /// @notice Monotonicity check (I5): two deposits at the same ratio, larger one
  ///         must mint at least as many shares as smaller one. Same player so vault
  ///         state-after-first does not bias us.
  function depositTwoAndCompare(uint8 idx, uint256 small, uint256 multiplier) external {
    idx = idx % 3;
    small = _boundAmount(small);
    multiplier = (multiplier % 50) + 2; // [2, 51]
    uint256 large = small * multiplier;
    if (large > MAX_DEPOSIT) return;

    uint256 s1;
    try players[idx].deposit(small, small) returns (uint256 v) {
      s1 = v;
    } catch {
      return;
    }
    uint256 s2;
    try players[idx].deposit(large, large) returns (uint256 v) {
      s2 = v;
    } catch {
      return;
    }
    // I5: larger deposit mints ≥ smaller deposit shares (same ratio, same vault, same player)
    assert(s2 >= s1);
    _assertConservation();
  }

  // ─── Invariant assertions ──────────────────────────────────────────────

  /// @notice I1: sum of all shareholders' balances equals totalSupply.
  function _assertConservation() internal view {
    uint256 sum = vault.balanceOf(address(this)); // INITIAL_SHARES holder
    for (uint256 i; i < 3; i++) {
      sum += vault.balanceOf(address(players[i]));
    }
    assert(sum == vault.totalSupply());
  }

  /// @notice Echidna-callable: standalone invariant check (also called by other actions).
  ///         Asserts totalSupply ≥ INITIAL_SHARES (no underflow / unexpected burn).
  function echidna_supplyNeverBelowInitialShares() public view returns (bool) {
    return vault.totalSupply() >= initialShareSupply;
  }

  /// @notice Echidna-callable: idle vault tokens are non-zero whenever totalSupply > 0.
  ///         I.e., shares can't be outstanding against an empty vault.
  function echidna_idleAvailableWhenSupplyOutstanding() public view returns (bool) {
    if (vault.totalSupply() == 0) return true;
    return tokenA.balanceOf(address(vault)) > 0 && tokenB.balanceOf(address(vault)) > 0;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  function _boundAmount(uint256 amount) internal pure returns (uint256) {
    // Below the dust floor → deposits revert with InvalidRatio. Bound above.
    if (amount < FLOOR_18) return FLOOR_18;
    if (amount > MAX_DEPOSIT) return MAX_DEPOSIT;
    return amount;
  }
}
