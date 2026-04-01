// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";

interface ISharedVaultFactory is ISharedCommon {
  event VaultCreated(address indexed owner, address indexed vault, string name);

  event ConfigManagerSet(address configManager);

  event VaultImplementationSet(address vaultImplementation);

  /// @notice Create a shared vault with initial token deposits.
  /// @param _operator Initial vault operator (address(0) = no operator until set by owner).
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    address _operator
  ) external payable returns (address vault);

  /// @notice Create a shared vault with initial deposits and execute multiple strategy actions.
  /// @param _operator Initial vault operator (address(0) = no operator until set by owner).
  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    address _operator,
    address[] calldata strategies,
    bytes[] calldata strategiesData,
    uint256[] calldata ethValues
  ) external payable returns (address vault);

  function isVault(address vault) external view returns (bool);
}
