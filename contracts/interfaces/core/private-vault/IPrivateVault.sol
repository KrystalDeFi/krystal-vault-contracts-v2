// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IPrivateCommon.sol";

interface IPrivateVault is IPrivateCommon {
  event SetVaultAdmin(address indexed vaultFactory, address indexed _address, bool indexed _isAdmin);

  error InvalidMulticallParams();

  error InvalidStrategy(address strategy);

  error StrategyDelegateCallFailed();

  error Paused();

  function initialize(address _owner, address _configManager) external;

  function multicall(address[] calldata targets, bytes[] calldata data, CallType[] calldata callTypes) external payable;

  function sweepNativeToken(uint256 amount) external;

  function sweepToken(address[] calldata tokens, uint256[] calldata amounts) external;

  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds) external;

  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds, uint256[] calldata _amounts) external;

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;
}
