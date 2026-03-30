// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";

interface ISharedVaultFactory is ISharedCommon {
  event VaultCreated(address indexed owner, address indexed vault, string name);

  event ConfigManagerSet(address configManager);

  event VaultImplementationSet(address vaultImplementation);

  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts
  ) external returns (address vault);

  function createVault(
    string calldata name,
    address[4] calldata tokens,
    uint256[4] calldata initialAmounts,
    address[] calldata strategies,
    bytes[] calldata strategiesData,
    uint256[] calldata ethValues
  ) external payable returns (address vault);

  function isVault(address vault) external view returns (bool);
}
