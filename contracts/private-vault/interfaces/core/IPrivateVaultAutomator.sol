// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./IPrivateCommon.sol";
import "./IPrivateVault.sol";

interface IPrivateVaultAutomator is IPrivateCommon {
  error InvalidSignature();

  error OrderCancelled();

  event CancelOrder(address user, bytes32 hash, bytes signature);

  function executeMulticallWithAgentAllowance(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external;

  function executeMulticallWithUserOrder(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  function cancelOrder(bytes32 hash, bytes memory signature) external;

  function isOrderCancelled(bytes memory signature) external view returns (bool);

  function grantOperator(address operator) external;

  function revokeOperator(address operator) external;
}
