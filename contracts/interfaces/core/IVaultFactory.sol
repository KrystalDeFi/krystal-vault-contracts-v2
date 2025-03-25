// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IVaultFactory is ICommon {
  event VaultCreated(address owner, address vault, VaultCreateParams params);

  event ConfigManagerSet(address configManager);

  event VaultImplementationSet(address vaultImplementation);

  event PlatformFeeRecipientSet(address platformFeeRecipient);

  event PlatformFeeBasisPointSet(uint16 platformFeeBasisPoint);

  error InvalidOwnerFee();
  error InvalidPrincipalToken();

  function createVault(VaultCreateParams memory params) external payable returns (address vault);

  function setConfigManager(address _configManager) external;

  function setVaultImplementation(address _vaultImplementation) external;

  function setPlatformFeeRecipient(address _platformFeeRecipient) external;

  function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) external;

  function WETH() external view returns (address);
}
