// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import "./SharedVaultConfig.sol";

contract SharedVaultPlayer {
  address public immutable fuzzer;

  constructor() payable {
    fuzzer = msg.sender;
  }

  modifier onlyFuzzer() {
    require(msg.sender == fuzzer, "only fuzzer");
    _;
  }

  // ── Deposit ───────────────────────────────────────────────────────────────

  function callDeposit(
    address vault,
    uint256[4] memory amounts,
    uint16 slippageBps
  ) external onlyFuzzer returns (uint256 shares) {
    address[4] memory vaultTokens = ISharedVault(payable(vault)).getTokens();
    for (uint256 i; i < 4; i++) {
      if (vaultTokens[i] != address(0) && amounts[i] > 0) {
        IERC20(vaultTokens[i]).approve(vault, amounts[i]);
      }
    }
    shares = ISharedVault(payable(vault)).deposit(
      [amounts[0], amounts[1], amounts[2], amounts[3]],
      slippageBps
    );
  }

  // ── Withdraw ──────────────────────────────────────────────────────────────

  function callWithdraw(address vault, uint256 shares, bool unwrap) external onlyFuzzer returns (uint256[4] memory amounts) {
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    amounts = ISharedVault(payable(vault)).withdraw(shares, minAmounts, unwrap);
  }

  // ── Execute (LP operations, owner/admin only) ─────────────────────────────

  function callExecute(address vault, ISharedVault.Action[] memory actions) external onlyFuzzer {
    ISharedVault(payable(vault)).execute(actions);
  }

  // ── Factory: create vault ─────────────────────────────────────────────────

  function callCreateVault(
    address factory,
    string memory name,
    address[4] memory vaultTokens,
    uint256[4] memory initialAmounts,
    uint16 feeBps
  ) external onlyFuzzer returns (address vault) {
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

  function callWhitelistTarget(address configManager, address target, bool enabled) external onlyFuzzer {
    address[] memory targets = new address[](1);
    targets[0] = target;
    ISharedConfigManager(configManager).setWhitelistTargets(targets, enabled);
  }

  // ── Shares balance convenience ────────────────────────────────────────────

  function sharesBalance(address vault) external view returns (uint256) {
    return IERC20(vault).balanceOf(address(this));
  }
}
