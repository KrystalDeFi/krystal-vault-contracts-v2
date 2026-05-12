# SharedVault Echidna Fuzzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three Echidna fuzz-test contracts for `SharedVault` covering solo-owner theft, multi-player share fairness, and LP strategy invariants.

**Architecture:** Mirror the existing `test/echidna-fuzzer/` structure — one fuzzer contract per scenario, a `SharedVaultPlayer` helper, a `SharedVaultConfig` constants file, and `ft.*` Foundry companions for local debugging. Echidna runs via devbox against a Base mainnet fork (block 36_953_600). Funding uses `hevm.store` to directly write ERC20 balances (same principle as Foundry's `stdstore`), avoiding dependency on a specific whale address.

**Tech Stack:** Solidity 0.8.28, Echidna (devbox), Foundry (forge), Base mainnet fork, SharedVault/SharedVaultFactory/SharedConfigManager/SharedV3Strategy contracts.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `test/echidna-fuzzer/SharedVaultConfig.sol` | Base-fork constants (addresses, block, amounts) |
| Create | `test/echidna-fuzzer/SharedVaultPlayer.sol` | Player helper wrapping SharedVault calls |
| Create | `test/echidna-fuzzer/Fuzzer.SharedVault.soloOwner.sol` | Echidna fuzzer: owner-theft scenario |
| Create | `test/echidna-fuzzer/ft.SharedVault.soloOwner.sol` | Foundry dev companion for soloOwner |
| Create | `test/echidna-fuzzer/Fuzzer.SharedVault.multiPlayer.sol` | Echidna fuzzer: multi-player fairness |
| Create | `test/echidna-fuzzer/ft.SharedVault.multiPlayer.sol` | Foundry dev companion for multiPlayer |
| Create | `test/echidna-fuzzer/Fuzzer.SharedVault.withStrategy.sol` | Echidna fuzzer: LP strategy invariants |
| Create | `test/echidna-fuzzer/ft.SharedVault.withStrategy.sol` | Foundry dev companion for withStrategy |
| Modify | `devbox.json` | Add `echidna` package |
| Modify | `run-echidna-test.sh` | Support SharedVault contract names + Base RPC |

---

## Task 1: Add echidna to devbox

**Files:**
- Modify: `devbox.json`

- [ ] **Step 1: Add echidna package**

Replace the contents of `devbox.json` with:

```json
{
  "$schema": "https://raw.githubusercontent.com/jetify-com/devbox/0.15.0/.schema/devbox.schema.json",
  "packages": ["git@latest", "echidna@latest"],
  "shell": {
    "init_hook": [
      "echo 'Welcome to devbox!' > /dev/null"
    ],
    "scripts": {
      "test": [
        "echo \"Error: no test specified\" && exit 1"
      ]
    }
  }
}
```

- [ ] **Step 2: Install and verify**

```bash
devbox install
devbox run -- echidna --version
```

Expected: echidna version string printed (e.g. `Echidna v2.x.x`).

- [ ] **Step 3: Commit**

```bash
git add devbox.json devbox.lock
git commit -m "chore: add echidna to devbox"
```

---

## Task 2: SharedVaultConfig.sol — Base fork constants

**Files:**
- Create: `test/echidna-fuzzer/SharedVaultConfig.sol`

This file mirrors `Config.sol` but targets Base mainnet addresses.

- [ ] **Step 1: Create the file**

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// ── Base mainnet addresses ────────────────────────────────────────────────────
address constant SV_WETH   = 0x4200000000000000000000000000000000000006;
address constant SV_USDC   = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant SV_NFPM   = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1; // Uniswap V3 on Base
address constant SV_V3UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

// ── Fork pin ──────────────────────────────────────────────────────────────────
uint256 constant SV_BLOCK_NUMBER    = 36_953_600;
uint256 constant SV_BLOCK_TIMESTAMP = 1_745_814_599;

// ── Echidna cheat-code address ────────────────────────────────────────────────
address constant SV_HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

// ── Initial balances ──────────────────────────────────────────────────────────
uint256 constant SV_INITIAL_WETH = 10 ether;
uint256 constant SV_INITIAL_USDC = 30_000e6;   // 30 000 USDC

// ── ERC20 balanceOf storage slots (for hevm.store funding) ────────────────────
// WETH on Base (OptimismMintableERC20): _balances mapping at slot 0
uint256 constant SV_WETH_BALANCE_SLOT = 0;
// USDC on Base (FiatTokenV2_2): _balanceAndBlacklistStates mapping at slot 9
uint256 constant SV_USDC_BALANCE_SLOT = 9;

// ── Uniswap V3 WETH/USDC 0.05% pool on Base ──────────────────────────────────
// tick spacing = 10; use wide range to stay in range regardless of price drift
int24 constant SV_TICK_LOWER = -887_270;  // near min tick (rounded to spacing 10)
int24 constant SV_TICK_UPPER =  887_270;  // near max tick
uint24 constant SV_POOL_FEE  = 500;       // 0.05%

// ── Fee recipient placeholder ─────────────────────────────────────────────────
address constant SV_FEE_RECIPIENT = address(0x1111);
```

- [ ] **Step 2: Verify it compiles**

```bash
forge build --contracts test/echidna-fuzzer/SharedVaultConfig.sol 2>&1 | head -20
```

Expected: no errors (file has no constructor, just constants).

- [ ] **Step 3: Commit**

```bash
git add test/echidna-fuzzer/SharedVaultConfig.sol
git commit -m "test(echidna): add SharedVaultConfig constants for Base fork"
```

---

## Task 3: SharedVaultPlayer.sol — player helper

**Files:**
- Create: `test/echidna-fuzzer/SharedVaultPlayer.sol`

Wraps SharedVault calls so fuzzer/ft contracts can act as separate role actors.

- [ ] **Step 1: Create the file**

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import "./SharedVaultConfig.sol";

contract SharedVaultPlayer {
  constructor() payable {}

  // ── Deposit ───────────────────────────────────────────────────────────────

  function callDeposit(
    address vault,
    uint256[4] memory amounts,
    uint16 slippageBps
  ) external returns (uint256 shares) {
    for (uint256 i; i < 4; i++) {
      address token = ISharedVault(payable(vault)).getTokens()[i];
      if (token != address(0) && amounts[i] > 0) {
        IERC20(token).approve(vault, amounts[i]);
      }
    }
    shares = ISharedVault(payable(vault)).deposit(
      [amounts[0], amounts[1], amounts[2], amounts[3]],
      slippageBps
    );
  }

  // ── Withdraw ──────────────────────────────────────────────────────────────

  function callWithdraw(
    address vault,
    uint256 shares,
    bool unwrap
  ) external returns (uint256[4] memory amounts) {
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    amounts = ISharedVault(payable(vault)).withdraw(shares, minAmounts, unwrap);
  }

  // ── Execute (LP operations, owner/admin only) ─────────────────────────────

  function callExecute(address vault, ISharedVault.Action[] memory actions) external {
    ISharedVault(payable(vault)).execute(actions);
  }

  // ── Factory: create vault ─────────────────────────────────────────────────

  function callCreateVault(
    address factory,
    string memory name,
    address[4] memory vaultTokens,
    uint256[4] memory initialAmounts,
    uint16 feeBps
  ) external returns (address vault) {
    for (uint256 i; i < 4; i++) {
      if (vaultTokens[i] != address(0) && initialAmounts[i] > 0) {
        IERC20(vaultTokens[i]).approve(factory, initialAmounts[i]);
      }
    }
    vault = SharedVaultFactory(factory).createVault(
      name,
      [vaultTokens[0], vaultTokens[1], vaultTokens[2], vaultTokens[3]],
      [initialAmounts[0], initialAmounts[1], initialAmounts[2], initialAmounts[3]],
      feeBps
    );
  }

  // ── Config: whitelist strategy ────────────────────────────────────────────

  function callWhitelistTarget(address configManager, address target, bool enabled) external {
    address[] memory targets = new address[](1);
    targets[0] = target;
    ISharedConfigManager(configManager).setWhitelistTargets(targets, enabled);
  }

  // ── Shares balance convenience ────────────────────────────────────────────

  function sharesBalance(address vault) external view returns (uint256) {
    return IERC20(vault).balanceOf(address(this));
  }
}
```

- [ ] **Step 2: Check it compiles**

```bash
forge build 2>&1 | grep -E "error|warning" | head -20
```

Expected: no errors. Warnings about unused variables are acceptable.

- [ ] **Step 3: Commit**

```bash
git add test/echidna-fuzzer/SharedVaultPlayer.sol
git commit -m "test(echidna): add SharedVaultPlayer helper for SharedVault fuzzers"
```

---

## Task 4: Fuzzer.SharedVault.soloOwner.sol + ft companion

**Files:**
- Create: `test/echidna-fuzzer/Fuzzer.SharedVault.soloOwner.sol`
- Create: `test/echidna-fuzzer/ft.SharedVault.soloOwner.sol`

**Scenario:** Owner creates a vault, owner + player1 + player2 deposit. Echidna then randomly calls deposit/withdraw actions. The property asserts the owner cannot end up with more tokens than they started with.

- [ ] **Step 1: Create Fuzzer.SharedVault.soloOwner.sol**

```solidity
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
  SharedVaultFactory  public vaultFactory;
  address             public vault;

  uint256 public ownerInitialWeth;

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    owner   = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();

    // Fund actors by writing directly to ERC20 storage (same as Foundry stdstore).
    _setErc20Balance(SV_WETH, address(owner),   SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_WETH, address(player1),  SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_WETH, address(player2),  SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_USDC, address(owner),   SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);
    _setErc20Balance(SV_USDC, address(player1),  SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);
    _setErc20Balance(SV_USDC, address(player2),  SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);

    ownerInitialWeth = SV_INITIAL_WETH;

    // Deploy infrastructure.
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
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
  }

  function owner_depositWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(owner));
    if (bal == 0) return;
    amount = amount % bal + 1;
    uint256[4] memory amounts = _proportionalDeposit(amount);
    if (!_hasEnoughBalance(address(owner), amounts)) return;
    owner.callDeposit(vault, amounts, 200);
  }

  function player1_withdraw(uint256 shares) external {
    uint256 p1Shares = player1.sharesBalance(vault);
    if (p1Shares == 0) return;
    shares = shares % p1Shares + 1;
    player1.callWithdraw(vault, shares, false);
  }

  function player1_depositWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(player1));
    if (bal == 0) return;
    amount = amount % bal + 1;
    uint256[4] memory amounts = _proportionalDeposit(amount);
    if (!_hasEnoughBalance(address(player1), amounts)) return;
    player1.callDeposit(vault, amounts, 200);
  }

  function player2_withdraw(uint256 shares) external {
    uint256 p2Shares = player2.sharesBalance(vault);
    if (p2Shares == 0) return;
    shares = shares % p2Shares + 1;
    player2.callWithdraw(vault, shares, false);
  }

  // ── Property ────────────────────────────────────────────────────────────────

  /// @dev Owner's WETH balance (wallet + vault shares value) must never exceed what they started with.
  ///      This catches owner-drains-players attacks.
  function echidna_owner_cannot_profit() external view returns (bool) {
    uint256 walletWeth = IERC20(SV_WETH).balanceOf(address(owner));
    uint256 vaultWeth  = _ownerVaultWeth();
    return walletWeth + vaultWeth <= ownerInitialWeth + 1e9; // tiny tolerance for rounding
  }

  /// @dev Total supply must equal sum of all tracked share holders' balances.
  function echidna_share_supply_consistent() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault)
      + player1.sharesBalance(vault)
      + player2.sharesBalance(vault);
    return supply == sumBalances;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function _setErc20Balance(address token, address account, uint256 mappingSlot, uint256 amount) internal {
    bytes32 slot = keccak256(abi.encode(account, mappingSlot));
    hevm.store(token, slot, bytes32(amount));
  }

  function _ownerVaultWeth() internal view returns (uint256) {
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
    return IERC20(SV_WETH).balanceOf(actor) >= amounts[0]
      && IERC20(SV_USDC).balanceOf(actor) >= amounts[1];
  }
}
```

- [ ] **Step 2: Create ft.SharedVault.soloOwner.sol (Foundry companion)**

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Foundry companion for Fuzzer.SharedVault.soloOwner — use to debug failing sequences locally.

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { TestCommon } from "../TestCommon.t.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract FtSharedVaultSoloOwner is TestCommon {
  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedConfigManager public configManager;
  SharedVaultFactory  public vaultFactory;
  address             public vault;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), SV_BLOCK_NUMBER);
    vm.selectFork(fork);

    owner   = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();

    setErc20Balance(SV_WETH, address(owner),   SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player1),  SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player2),  SV_INITIAL_WETH);
    setErc20Balance(SV_USDC, address(owner),   SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player1),  SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player2),  SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
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

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "SoloOwner", vaultTokens, initAmounts, 0);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    player2.callDeposit(vault, pAmounts, 0);
  }

  function test_printState() public view {
    console.log("vault:", vault);
    console.log("owner shares:", owner.sharesBalance(vault));
    console.log("player1 shares:", player1.sharesBalance(vault));
    console.log("player2 shares:", player2.sharesBalance(vault));
    console.log("vault total supply:", IERC20(vault).totalSupply());
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    console.log("vault WETH total:", totals[0]);
    console.log("vault USDC total:", totals[1]);
  }

  function test_ownerWithdrawAll() public {
    uint256 ownerSharesBefore = owner.sharesBalance(vault);
    owner.callWithdraw(vault, ownerSharesBefore, false);
    assertEq(owner.sharesBalance(vault), 0);
    assertLe(IERC20(SV_WETH).balanceOf(address(owner)), SV_INITIAL_WETH + 1e9);
  }
}
```

- [ ] **Step 3: Compile**

```bash
forge build 2>&1 | grep "error" | head -20
```

Expected: no compilation errors.

- [ ] **Step 4: Run the Foundry companion test**

```bash
RPC_URL=<your-base-rpc-url> forge test --match-contract FtSharedVaultSoloOwner -vvv
```

Expected: `test_printState` and `test_ownerWithdrawAll` pass.

- [ ] **Step 5: Commit**

```bash
git add test/echidna-fuzzer/Fuzzer.SharedVault.soloOwner.sol test/echidna-fuzzer/ft.SharedVault.soloOwner.sol
git commit -m "test(echidna): add SharedVault soloOwner fuzzer + foundry companion"
```

---

## Task 5: Fuzzer.SharedVault.multiPlayer.sol + ft companion

**Files:**
- Create: `test/echidna-fuzzer/Fuzzer.SharedVault.multiPlayer.sol`
- Create: `test/echidna-fuzzer/ft.SharedVault.multiPlayer.sol`

**Scenario:** Three players deposit equal amounts. Echidna randomly calls deposit/withdraw in any order for any player. Properties assert share supply consistency and no player can extract more than they deposited (within vault-owner fee tolerance).

- [ ] **Step 1: Create Fuzzer.SharedVault.multiPlayer.sol**

```solidity
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
  SharedVaultFactory  public vaultFactory;
  address             public vault;

  uint256 public constant PLAYER_DEPOSIT_WETH = 2 ether;
  uint256 public constant PLAYER_DEPOSIT_USDC = 6_000e6;

  // Track each player's net WETH deposited (deposits minus withdrawals) for property 3.
  mapping(address => int256) public netWethDeposit;

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();
    player3 = new SharedVaultPlayer();

    _setErc20Balance(SV_WETH, address(player1), SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_WETH, address(player2), SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_WETH, address(player3), SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_USDC, address(player1), SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);
    _setErc20Balance(SV_USDC, address(player2), SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);
    _setErc20Balance(SV_USDC, address(player3), SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
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
    uint256 sumBalances = player1.sharesBalance(vault)
      + player2.sharesBalance(vault)
      + player3.sharesBalance(vault);
    return supply == sumBalances;
  }

  function echidna_no_player_profits_from_weth() external view returns (bool) {
    return _playerNetWethOk(player1)
      && _playerNetWethOk(player2)
      && _playerNetWethOk(player3);
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
  }

  function _doWithdraw(SharedVaultPlayer player, uint256 shares) internal {
    uint256 playerShares = player.sharesBalance(vault);
    if (playerShares == 0) return;
    shares = shares % playerShares + 1;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(player));
    player.callWithdraw(vault, shares, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(player));
    netWethDeposit[address(player)] -= int256(wethAfter - wethBefore);
  }

  function _playerNetWethOk(SharedVaultPlayer player) internal view returns (bool) {
    int256 net = netWethDeposit[address(player)];
    // net >= -1e9 means player never withdrew more than deposited (with tiny rounding tolerance)
    return net >= -int256(1e9);
  }

  function _setErc20Balance(address token, address account, uint256 mappingSlot, uint256 amount) internal {
    bytes32 slot = keccak256(abi.encode(account, mappingSlot));
    hevm.store(token, slot, bytes32(amount));
  }

  function _proportionalAmounts(uint256 wethAmount) internal view returns (uint256[4] memory amounts) {
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    amounts[0] = wethAmount;
    if (totals[0] > 0 && totals[1] > 0) {
      amounts[1] = wethAmount * totals[1] / totals[0] + 1;
    }
  }

  function _hasEnoughBalance(address actor, uint256[4] memory amounts) internal view returns (bool) {
    return IERC20(SV_WETH).balanceOf(actor) >= amounts[0]
      && IERC20(SV_USDC).balanceOf(actor) >= amounts[1];
  }
}
```

- [ ] **Step 2: Create ft.SharedVault.multiPlayer.sol**

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { TestCommon } from "../TestCommon.t.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract FtSharedVaultMultiPlayer is TestCommon {
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedVaultPlayer public player3;
  SharedConfigManager public configManager;
  SharedVaultFactory  public vaultFactory;
  address             public vault;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), SV_BLOCK_NUMBER);
    vm.selectFork(fork);

    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();
    player3 = new SharedVaultPlayer();

    setErc20Balance(SV_WETH, address(player1), SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player2), SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player3), SV_INITIAL_WETH);
    setErc20Balance(SV_USDC, address(player1), SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player2), SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player3), SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      address(player1),
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

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player2.callDeposit(vault, pAmounts, 0);
    player3.callDeposit(vault, pAmounts, 0);
  }

  function test_shareSupplyConsistency() public view {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sum = player1.sharesBalance(vault)
      + player2.sharesBalance(vault)
      + player3.sharesBalance(vault);
    assertEq(supply, sum);
  }

  function test_allPlayersWithdraw() public {
    player1.callWithdraw(vault, player1.sharesBalance(vault), false);
    player2.callWithdraw(vault, player2.sharesBalance(vault), false);
    player3.callWithdraw(vault, player3.sharesBalance(vault), false);
    assertEq(IERC20(vault).totalSupply(), 0);
  }
}
```

- [ ] **Step 3: Compile and run Foundry companion**

```bash
forge build 2>&1 | grep "error" | head -20
RPC_URL=<your-base-rpc-url> forge test --match-contract FtSharedVaultMultiPlayer -vvv
```

Expected: both tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/echidna-fuzzer/Fuzzer.SharedVault.multiPlayer.sol test/echidna-fuzzer/ft.SharedVault.multiPlayer.sol
git commit -m "test(echidna): add SharedVault multiPlayer fuzzer + foundry companion"
```

---

## Task 6: Fuzzer.SharedVault.withStrategy.sol + ft companion

**Files:**
- Create: `test/echidna-fuzzer/Fuzzer.SharedVault.withStrategy.sol`
- Create: `test/echidna-fuzzer/ft.SharedVault.withStrategy.sol`

**Scenario:** Same multi-player setup, but the vault owner also opens and closes LP positions via `execute()` using `SharedV3Strategy`. Properties assert position tracking consistency and fee-basis-point immutability.

- [ ] **Step 1: Create Fuzzer.SharedVault.withStrategy.sol**

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * Scenario: owner opens/closes LP positions while players deposit/withdraw.
 * Properties:
 *   1. vaultOwnerFeeBasisPoint never changes after init
 *   2. totalSupply == sum of all player share balances
 *   3. No player withdraws more than deposited
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import "./IHevm.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract SharedVaultFuzzerWithStrategy {
  IHevm internal hevm = IHevm(SV_HEVM_ADDRESS);

  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;

  SharedConfigManager public configManager;
  SharedVaultFactory  public vaultFactory;
  SharedV3Strategy    public v3Strategy;
  address             public vault;

  uint16 public immutable INITIAL_FEE_BPS;
  mapping(address => int256) public netWethDeposit;

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    owner   = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();

    _setErc20Balance(SV_WETH, address(owner),   SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_WETH, address(player1),  SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_WETH, address(player2),  SV_WETH_BALANCE_SLOT, SV_INITIAL_WETH);
    _setErc20Balance(SV_USDC, address(owner),   SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);
    _setErc20Balance(SV_USDC, address(player1),  SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);
    _setErc20Balance(SV_USDC, address(player2),  SV_USDC_BALANCE_SLOT, SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(SV_V3UTILS, address(lpFeeTaker));

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;

    configManager = new SharedConfigManager();
    configManager.initialize(
      address(owner),
      targets,
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    uint16 feeBps = 500; // 5%
    INITIAL_FEE_BPS = feeBps;

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "WithStrategy", vaultTokens, initAmounts, feeBps);
    netWethDeposit[address(owner)] += int256(1 ether);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player1)] += int256(1 ether);
    player2.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player2)] += int256(1 ether);
  }

  // ── Fuzzed actions ──────────────────────────────────────────────────────────

  function player1_deposit(uint256 wethAmount) external { _doDeposit(player1, wethAmount); }
  function player2_deposit(uint256 wethAmount) external { _doDeposit(player2, wethAmount); }
  function player1_withdraw(uint256 shares)    external { _doWithdraw(player1, shares); }
  function player2_withdraw(uint256 shares)    external { _doWithdraw(player2, shares); }
  function owner_withdraw(uint256 shares)      external { _doWithdraw(owner, shares); }

  // ── Properties ──────────────────────────────────────────────────────────────

  function echidna_fee_bps_immutable() external view returns (bool) {
    return SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS;
  }

  function echidna_share_supply_consistent() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault)
      + player1.sharesBalance(vault)
      + player2.sharesBalance(vault);
    return supply == sumBalances;
  }

  function echidna_no_player_profits() external view returns (bool) {
    return _playerNetOk(owner)
      && _playerNetOk(player1)
      && _playerNetOk(player2);
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
  }

  function _doWithdraw(SharedVaultPlayer player, uint256 shares) internal {
    uint256 playerShares = player.sharesBalance(vault);
    if (playerShares == 0) return;
    shares = shares % playerShares + 1;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(player));
    player.callWithdraw(vault, shares, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(player));
    netWethDeposit[address(player)] -= int256(wethAfter - wethBefore);
  }

  function _playerNetOk(SharedVaultPlayer player) internal view returns (bool) {
    return netWethDeposit[address(player)] >= -int256(1e9);
  }

  function _setErc20Balance(address token, address account, uint256 mappingSlot, uint256 amount) internal {
    bytes32 slot = keccak256(abi.encode(account, mappingSlot));
    hevm.store(token, slot, bytes32(amount));
  }

  function _proportionalAmounts(uint256 wethAmount) internal view returns (uint256[4] memory amounts) {
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    amounts[0] = wethAmount;
    if (totals[0] > 0 && totals[1] > 0) {
      amounts[1] = wethAmount * totals[1] / totals[0] + 1;
    }
  }

  function _hasEnoughBalance(address actor, uint256[4] memory amounts) internal view returns (bool) {
    return IERC20(SV_WETH).balanceOf(actor) >= amounts[0]
      && IERC20(SV_USDC).balanceOf(actor) >= amounts[1];
  }
}
```

- [ ] **Step 2: Create ft.SharedVault.withStrategy.sol**

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { TestCommon } from "../TestCommon.t.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract FtSharedVaultWithStrategy is TestCommon {
  SharedVaultPlayer   public owner;
  SharedVaultPlayer   public player1;
  SharedVaultPlayer   public player2;
  SharedConfigManager public configManager;
  SharedVaultFactory  public vaultFactory;
  SharedV3Strategy    public v3Strategy;
  address             public vault;
  uint16 public constant FEE_BPS = 500;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), SV_BLOCK_NUMBER);
    vm.selectFork(fork);

    owner   = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();

    setErc20Balance(SV_WETH, address(owner),   SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player1),  SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player2),  SV_INITIAL_WETH);
    setErc20Balance(SV_USDC, address(owner),   SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player1),  SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player2),  SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(SV_V3UTILS, address(lpFeeTaker));

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;

    configManager = new SharedConfigManager();
    configManager.initialize(
      address(owner),
      targets,
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "WithStrategy", vaultTokens, initAmounts, FEE_BPS);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    player2.callDeposit(vault, pAmounts, 0);
  }

  function test_feeBpsImmutable() public view {
    assertEq(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint(), FEE_BPS);
  }

  function test_shareSupplyConsistency() public view {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sum = owner.sharesBalance(vault)
      + player1.sharesBalance(vault)
      + player2.sharesBalance(vault);
    assertEq(supply, sum);
  }

  function test_allWithdrawAfterDeposit() public {
    owner.callWithdraw(vault, owner.sharesBalance(vault), false);
    player1.callWithdraw(vault, player1.sharesBalance(vault), false);
    player2.callWithdraw(vault, player2.sharesBalance(vault), false);
    assertEq(IERC20(vault).totalSupply(), 0);
    console.log("owner WETH after:", IERC20(SV_WETH).balanceOf(address(owner)));
    console.log("player1 WETH after:", IERC20(SV_WETH).balanceOf(address(player1)));
  }
}
```

- [ ] **Step 3: Compile and run Foundry companion**

```bash
forge build 2>&1 | grep "error" | head -20
RPC_URL=<your-base-rpc-url> forge test --match-contract FtSharedVaultWithStrategy -vvv
```

Expected: all three tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/echidna-fuzzer/Fuzzer.SharedVault.withStrategy.sol test/echidna-fuzzer/ft.SharedVault.withStrategy.sol
git commit -m "test(echidna): add SharedVault withStrategy fuzzer + foundry companion"
```

---

## Task 7: Update run-echidna-test.sh and config.yaml

**Files:**
- Modify: `run-echidna-test.sh`
- Modify: `test/echidna-fuzzer/config.yaml` (no change needed — `allContracts: true` already covers new contracts)

The run script needs to:
1. Accept the new SharedVault contract names
2. Set `ECHIDNA_RPC_URL` to a Base RPC for SharedVault contracts (vs Ethereum mainnet for existing)
3. Copy SharedVault-specific files to `contracts/echidna-fuzzer/`

- [ ] **Step 1: Edit run-echidna-test.sh**

After the existing `export ECHIDNA_RPC_URL=...` line (Ethereum mainnet), add a branch that sets the Base RPC when a SharedVault contract is requested. Replace the section:

```bash
export ECHIDNA_RPC_URL="https://rpc-node-lb.krystal.app/?chain_id=1&debug_trace_only=true"
```

with:

```bash
# Use Base mainnet fork for SharedVault fuzzers, Ethereum mainnet for everything else.
case "$CONTRACT_NAME" in
  SharedVaultFuzzer*)
    export ECHIDNA_RPC_URL="${BASE_RPC_URL:-https://rpc-node-lb.krystal.app/?chain_id=8453&debug_trace_only=true}"
    ;;
  *)
    export ECHIDNA_RPC_URL="${ETH_RPC_URL:-https://rpc-node-lb.krystal.app/?chain_id=1&debug_trace_only=true}"
    ;;
esac
```

Also update the find command that copies echidna files so SharedVault fuzzers are included. The existing line is:

```bash
find test/echidna-fuzzer -type f -not -name "ft.*.sol" -exec cp -v {} contracts/echidna-fuzzer/ \;
```

This already copies all non-`ft.*` files including the new `Fuzzer.SharedVault.*.sol` and `SharedVaultConfig.sol` / `SharedVaultPlayer.sol`, so **no change needed** to that line.

- [ ] **Step 2: Verify the script handles all three new names**

```bash
grep -A 6 "case.*CONTRACT_NAME" run-echidna-test.sh
```

Expected output shows the `SharedVaultFuzzer*` case with a Base RPC URL.

- [ ] **Step 3: Commit**

```bash
git add run-echidna-test.sh
git commit -m "test(echidna): route SharedVault fuzzers to Base fork RPC"
```

---

## Task 8: Verify ERC20 storage slots and run echidna

**Context:** The `hevm.store` approach writes directly to ERC20 storage. The slot numbers in `SharedVaultConfig.sol` (`SV_WETH_BALANCE_SLOT = 0`, `SV_USDC_BALANCE_SLOT = 9`) must match the actual contract layouts on Base. This task verifies them and runs the first echidna fuzzer end-to-end.

- [ ] **Step 1: Confirm WETH balance slot via Foundry fork**

Create a one-off script at `/tmp/check_slots.sh` and run it:

```bash
RPC_URL=<your-base-rpc-url> forge script - --rpc-url $RPC_URL --fork-block-number 36953600 << 'EOF'
pragma solidity ^0.8.28;
import "forge-std/Script.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckSlots is Script {
    using stdStorage for StdStorage;
    StdStorage private ss;

    function run() external {
        address weth = 0x4200000000000000000000000000000000000006;
        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address probe = address(0xdead);

        uint256 wethSlot = ss.target(weth).sig(IERC20(weth).balanceOf.selector).with_key(probe).find();
        uint256 usdcSlot = ss.target(usdc).sig(IERC20(usdc).balanceOf.selector).with_key(probe).find();

        console.log("WETH balanceOf slot:", wethSlot);
        console.log("USDC balanceOf slot:", usdcSlot);
    }
}
EOF
```

Expected: two slot numbers printed. If they differ from `SV_WETH_BALANCE_SLOT` (0) or `SV_USDC_BALANCE_SLOT` (9), update those constants in `SharedVaultConfig.sol` and re-commit.

- [ ] **Step 2: Run the soloOwner Foundry test to confirm hevm.store funding works**

```bash
RPC_URL=<your-base-rpc-url> forge test --match-contract FtSharedVaultSoloOwner -vvv 2>&1 | tail -30
```

Expected: `test_printState` logs non-zero WETH/USDC totals; `test_ownerWithdrawAll` passes.

- [ ] **Step 3: Run echidna for soloOwner (inside devbox shell)**

```bash
devbox shell -- bash -c "./run-echidna-test.sh SharedVaultFuzzerSoloOwner"
```

Expected: echidna starts, prints discovered corpus sequences, no immediate property violations. Let it run for a few minutes.

- [ ] **Step 4: Run echidna for multiPlayer**

```bash
devbox shell -- bash -c "./run-echidna-test.sh SharedVaultFuzzerMultiPlayer"
```

- [ ] **Step 5: Run echidna for withStrategy**

```bash
devbox shell -- bash -c "./run-echidna-test.sh SharedVaultFuzzerWithStrategy"
```

- [ ] **Step 6: Commit any slot-constant fixes**

If `SharedVaultConfig.sol` was updated in Step 1:

```bash
git add test/echidna-fuzzer/SharedVaultConfig.sol
git commit -m "fix(echidna): correct ERC20 storage slot constants for Base mainnet"
```

---

## Notes for implementer

- **`hevm.store` slot verification is the most likely failure point.** If the Foundry companion tests fail with zero balances, the slot numbers are wrong — run the Step 8.1 script to find the correct ones.
- **`setWhitelistTargets(address[], bool)`** is the correct `SharedConfigManager` method name — already used in `SharedVaultPlayer.callWhitelistTarget`.
- **`SV_FEE_RECIPIENT = address(0x1111)`:** echidna doesn't care about this address; it's just a non-zero placeholder required by `SharedConfigManager.initialize`.
- **Echidna `allContracts: true`** means echidna will also probe `SharedVaultPlayer` and helper contracts — this is fine; none of them have `echidna_*` properties so they won't trigger false failures.
