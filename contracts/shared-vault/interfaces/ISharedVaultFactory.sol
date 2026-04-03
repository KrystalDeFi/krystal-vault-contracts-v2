// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";

interface ISharedVaultFactory is ISharedCommon {
  error DuplicateVaultName();

  event VaultCreated(address indexed owner, address indexed vault, string name);

  event ConfigManagerSet(address configManager);

  event VaultImplementationSet(address vaultImplementation);

  /// @notice Create a shared vault with initial token deposits.
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts
  ) external payable returns (address vault);

  /// @notice Create a shared vault with initial deposits and execute multiple strategy actions.
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data
  ) external payable returns (address vault);

  function isVault(address vault) external view returns (bool);
}
