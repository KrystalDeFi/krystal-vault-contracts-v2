// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";
import "./ISharedVault.sol";

interface ISharedVaultFactory is ISharedCommon {
  error DuplicateVaultName();

  event VaultCreated(address indexed owner, address indexed vault, string name);

  event ConfigManagerSet(address configManager);

  event VaultImplementationSet(address vaultImplementation);

  /// @notice Create a shared vault with initial token deposits.
  /// @param vaultOwnerFeeBasisPoint Basis points of LP performance/collection fees routed to the
  ///        vault owner on proportional exits (max 10_000). **Locked at vault creation** — there is
  ///        no setter on `ISharedVault`, so depositors can rely on the value seen at creation time.
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    uint16 vaultOwnerFeeBasisPoint
  ) external payable returns (address vault);

  /// @notice Create a shared vault with initial deposits and run `execute(actions)` once (same semantics as `ISharedVault.execute`).
  /// @param vaultOwnerFeeBasisPoint Locked at creation — see overload above for full semantics.
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    uint16 vaultOwnerFeeBasisPoint,
    ISharedVault.Action[] calldata actions
  ) external payable returns (address vault);

  function isVault(address vault) external view returns (bool);
}
