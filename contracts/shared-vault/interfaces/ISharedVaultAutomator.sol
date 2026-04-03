// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";
import "./ISharedVault.sol";

interface ISharedVaultAutomator is ISharedCommon {
  error InvalidSignature();

  error OrderCancelled();

  event CancelOrder(address user, bytes32 hash, bytes signature);

  /// @notice Execute actions against a vault using a long-lived AgentAllowance signature.
  /// @dev **Security note**: the AgentAllowance struct commits only to (vault, signatureTime,
  ///      expirationTime). It does NOT restrict which strategies, targets, or calldata the
  ///      operator may use — any whitelisted operation on the vault is permitted until expiry.
  ///      This is a broad delegation by design; vault owners should use short expiration
  ///      windows and `cancelOrder` for early revocation. For one-time scoped operations,
  ///      prefer `executeWithUserOrder`.
  /// @param vault Vault to operate on
  /// @param actions Same shape as `ISharedVault.execute` (`CallType.DELEGATECALL` for strategies, `CALL` for swaps)
  /// @param abiEncodedAgentAllowance ABI-encoded AgentAllowance struct
  /// @param signature Vault owner's EIP-712 signature over the AgentAllowance
  function executeWithAgentAllowance(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external;

  /// @notice Execute actions against a vault using a user order signature.
  /// @param vault Vault to operate on
  /// @param actions Same shape as `ISharedVault.execute`
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeWithUserOrder(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  /// @notice Cancel an order so it can never be replayed
  /// @param hash EIP-712 digest that was signed
  /// @param signature The signature to cancel (must have been signed by msg.sender)
  function cancelOrder(bytes32 hash, bytes memory signature) external;

  /// @notice Check whether an order signature has been cancelled
  function isOrderCancelled(bytes calldata signature) external view returns (bool);

  /// @notice Grant operator role to an address
  function grantOperator(address operator) external;

  /// @notice Revoke operator role from an address
  function revokeOperator(address operator) external;
}
