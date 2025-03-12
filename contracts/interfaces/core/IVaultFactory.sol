// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IVaultFactory is ICommon {
  event VaultCreated(address owner, address vault, VaultCreateParams params);

  event WhitelistManagerSet(address whitelistManager);

  event VaultImplementationSet(address vaultImplementation);

  event VaultAutomatorSet(address vaultAutomator);

  event PlatformFeeRecipientSet(address platformFeeRecipient);

  event PlatformFeeBasisPointSet(uint16 platformFeeBasisPoint);

  error InvalidOwnerFee();
  error InvalidPrincipleToken();

  function createVault(VaultCreateParams memory params) external payable returns (address vault);

  function setWhitelistManager(address _whitelistManager) external;

  function setVaultImplementation(address _vaultImplementation) external;

  function setVaultAutomator(address _vaultAutomator) external;

  function setPlatformFeeRecipient(address _platformFeeRecipient) external;

  function setPlatformFeeBasisPoint(uint16 _platformFeeBasisPoint) external;
}
