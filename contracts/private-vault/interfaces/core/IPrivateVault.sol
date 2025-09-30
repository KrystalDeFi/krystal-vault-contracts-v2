// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IPrivateCommon.sol";

interface IPrivateVault is IPrivateCommon {
  event SetVaultAdmin(address indexed vaultFactory, address indexed _address, bool indexed _isAdmin);

  error InvalidMulticallParams();

  error InvalidTarget(address strategy);

  error StrategyDelegateCallFailed();

  error Paused();

  function vaultOwner() external view returns (address);

  function initialize(address _owner, address _configManager) external;

  function multicall(address[] calldata targets, bytes[] calldata data, CallType[] calldata callTypes) external payable;

  function depositErc20Tokens(address[] calldata tokens, uint256[] calldata amounts) external;

  function depositErc721Tokens(address[] calldata tokens, uint256[] calldata tokenIds) external;

  function depositErc1155Tokens(address[] calldata tokens, uint256[] calldata tokenIds, uint256[] calldata amounts)
    external;

  function sweepNativeToken(uint256 amount) external;

  function sweepToken(address[] calldata tokens, uint256[] calldata amounts) external;

  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds) external;

  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds, uint256[] calldata _amounts) external;

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;
}
