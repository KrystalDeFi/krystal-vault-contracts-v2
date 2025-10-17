// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IPrivateCommon.sol";
import "./IPrivateConfigManager.sol";

interface IPrivateVault is IPrivateCommon {
  error InvalidMulticallParams();

  error InvalidTarget(address strategy);

  error StrategyDelegateCallFailed();

  error Paused();

  event VaultMulticall(address indexed vaultFactory, address[] targets, bytes[] data, CallType[] callTypes);

  event VaultSweepNativeToken(address indexed caller, uint256 amount);
  event VaultSweepToken(address indexed caller, address[] tokens, uint256[] amounts);
  event VaultSweepERC721(address indexed caller, address[] tokens, uint256[] tokenIds);
  event VaultSweepERC1155(address indexed caller, address[] tokens, uint256[] tokenIds, uint256[] amounts);

  event VaultDepositErc20Tokens(address indexed caller, address[] tokens, uint256[] amounts);
  event VaultDepositErc721Tokens(address indexed caller, address[] tokens, uint256[] tokenIds);
  event VaultDepositErc1155Tokens(address indexed caller, address[] tokens, uint256[] tokenIds, uint256[] amounts);

  event SetVaultAdmin(address indexed vaultFactory, address indexed _address, bool indexed _isAdmin);

  function name() external view returns (string memory);

  function vaultOwner() external view returns (address);

  function configManager() external view returns (IPrivateConfigManager);

  function initialize(address _owner, address _configManager, string calldata _name) external;

  function multicall(
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes
  ) external payable;

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
