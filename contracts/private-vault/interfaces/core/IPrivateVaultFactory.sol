// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IPrivateCommon.sol";

interface IPrivateVaultFactory is IPrivateCommon {
  event VaultCreated(address indexed owner, address indexed vault, string name);

  event ConfigManagerSet(address configManager);

  event VaultImplementationSet(address vaultImplementation);

  function createVault(string calldata name) external returns (address vault);

  function createVault(
    string calldata name,
    address[] calldata tokens,
    uint256[] calldata amounts,
    address[] calldata nfts721,
    uint256[] calldata nfts721TokenIds,
    address[] calldata nfts1155,
    uint256[] calldata nfts1155TokenIds,
    uint256[] calldata nfts1155Amounts,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes
  ) external payable returns (address vault);

  function isVault(address vault) external view returns (bool);
}
